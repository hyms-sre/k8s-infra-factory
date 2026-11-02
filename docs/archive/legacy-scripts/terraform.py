#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
terraform.py — 生成 Kubernetes 集群的 Terraform 变量文件 (tfvars)

用途
    把「集群拓扑」用命令行描述清楚，一键产出 examples/kubernetes/terraform.tfvars，
    避免手工复制粘贴 tfvars 时改漏 IP / 规格 / 版本号。

支持的配置项
    · 主机名     : --cluster-name / --vm-name-prefix / --date
    · IP 分配    : --ip-start 顺序分配, 或 --spec 精确指定; 自动查重与越界校验
    · 凭据       : --password / --generate-password, --ssh-key-file / --ssh-key
    · 规格       : 每个角色独立的 cpu / 内存 / 系统盘 / 数据盘
    · 网络插件   : --cni cilium|calico|flannel|none
    · 虚拟机数量 : --masters N --workers N --extra role:count ... (不限台数)
    · 复杂拓扑   : --spec topology.json (也支持 YAML, 需 PyYAML)

示例
    # 1 master + 5 worker + 1 harbor, 用 Calico, 自定义密码
    ./terraform.py --masters 1 --workers 5 --registry 1 \\
        --cni calico --password 'Str0ng!Pass' \\
        --ssh-key-file ~/.ssh/id_ed25519.pub \\
        --output examples/kubernetes/terraform.tfvars

    # 只打印不落盘
    ./terraform.py --masters 3 --workers 3 --dry-run

    # 从拓扑文件生成 (适合超大规模 / 固定 IP 场景)
    ./terraform.py --spec examples/kubernetes/topology.example.json

真值同步
    本脚本中的 K8S_VERSIONS / CNI_CHOICES / ROLE_DEFAULTS 必须与
    locals.tf 的 k8s_catalog / cni_catalog / role_defaults 保持一致。
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import secrets
import string
import sys
from datetime import date
from pathlib import Path

# --------------------------------------------------------------------------- #
# 与 locals.tf 保持同步的常量
# --------------------------------------------------------------------------- #
K8S_VERSIONS = ["v1.33", "v1.34", "v1.35", "v1.36", "v1.37"]
CNI_CHOICES = ["cilium", "calico", "flannel", "none"]

# 角色 -> (短名, 默认规格)
ROLE_DEFAULTS = {
    "control-plane": {"short": "master", "cpu": 4, "memory": 4096, "disk": 40, "data_disk": 50},
    "worker":        {"short": "worker", "cpu": 4, "memory": 8192, "disk": 40, "data_disk": 50},
    "registry":      {"short": "harbor", "cpu": 4, "memory": 4096, "disk": 40, "data_disk": 200},
    "gateway":       {"short": "openwrt", "cpu": 2, "memory": 4096, "disk": 40, "data_disk": 0},
}

DEFAULT_NAMESERVERS = ["172.16.222.210", "223.5.5.5", "119.29.29.29"]

# --------------------------------------------------------------------------- #
# 工具
# --------------------------------------------------------------------------- #

def die(msg: str, code: int = 2) -> "None":
    print(f"[ERROR] {msg}", file=sys.stderr)
    sys.exit(code)


def norm_path(raw: str) -> str:
    """归一化路径: 展开 ~, 并把 Git Bash/MSYS 风格 (/c/Users/...) 转成 C:/Users/..."""
    p = os.path.expanduser(raw)
    if sys.platform == "win32" and len(p) > 2 and p[0] == "/" and p[2] == "/" and p[1].isalpha():
        p = f"{p[1].upper()}:{p[2:]}"
    return p


def gen_password(length: int = 20) -> str:
    """生成不含引号/反斜杠的强口令 (避免写进 HCL 时转义出问题)。"""
    alphabet = string.ascii_letters + string.digits + "!@#%^&*-_=+"
    return "".join(secrets.choice(alphabet) for _ in range(length))


def read_ssh_keys(files: list[str], inline: list[str]) -> list[str]:
    keys: list[str] = []
    for raw in files or []:
        p = Path(norm_path(raw))
        if not p.is_file():
            die(f"SSH 公钥文件不存在: {raw}")
        content = p.read_text(encoding="utf-8", errors="replace").strip()
        if not content:
            die(f"SSH 公钥文件为空: {raw}")
        keys.append(content)
    keys.extend(k.strip() for k in (inline or []) if k.strip())
    if not keys:
        # 自动探测常见公钥
        for cand in ("~/.ssh/id_ed25519.pub", "~/.ssh/id_rsa.pub"):
            p = Path(norm_path(cand))
            if p.is_file() and p.read_text(encoding="utf-8").strip():
                keys.append(p.read_text(encoding="utf-8").strip())
                print(f"[INFO] 自动使用 SSH 公钥: {cand}")
                break
    if not keys:
        die("未提供 SSH 公钥。请用 --ssh-key-file 或 --ssh-key 指定 "
            "(否则新建的 VM 将无法登录)。")
    return keys


def parse_extra(items: list[str] | None) -> list[tuple[str, int]]:
    """--extra worker:3 registry:1 -> [('worker', 3), ('registry', 1)]"""
    out: list[tuple[str, int]] = []
    for it in items or []:
        if ":" not in it:
            die(f"--extra 格式应为 role:count, 收到 {it!r}")
        role, _, cnt = it.partition(":")
        role = role.strip()
        if role not in ROLE_DEFAULTS:
            die(f"--extra 角色 {role!r} 无效, 可选: {', '.join(ROLE_DEFAULTS)}")
        try:
            n = int(cnt)
        except ValueError:
            die(f"--extra 数量必须是整数, 收到 {cnt!r}")
        if n < 0:
            die(f"--extra 数量不能为负: {it!r}")
        if n:
            out.append((role, n))
    return out


# --------------------------------------------------------------------------- #
# 拓扑构建
# --------------------------------------------------------------------------- #

def build_nodes(args) -> list[dict]:
    """按 顺序 生成节点列表: control-plane -> worker -> 其它角色"""
    # 1) 收集角色顺序与数量
    plan: list[tuple[str, int]] = []
    if args.masters:
        plan.append(("control-plane", args.masters))
    if args.workers:
        plan.append(("worker", args.workers))
    if args.registry:
        plan.append(("registry", args.registry))
    if args.gateway:
        plan.append(("gateway", args.gateway))
    plan.extend(parse_extra(args.extra))

    if not plan:
        die("至少要有一个节点。请用 --masters/--workers/--registry/--gateway 或 --extra 指定。")
    if args.masters > 1 and args.masters % 2 == 0:
        print("[WARN] etcd 建议奇数个控制平面 (1/3/5)，当前为 "
              f"{args.masters}。", file=sys.stderr)

    # 2) 逐节点分配
    net = ipaddress.ip_network(args.network, strict=False)
    gateway_ip = ipaddress.ip_address(args.gateway_ip)
    if gateway_ip not in net:
        die(f"网关 {gateway_ip} 不在网段 {net} 内")

    used: dict[str, str] = {}          # ip -> 描述
    used[args.gateway_ip] = "gateway"

    counters: dict[str, int] = {}
    nodes: list[dict] = []
    next_ip = int(ipaddress.ip_address(args.ip_start)) if args.ip_start else None

    def alloc_ip(desc: str) -> str:
        nonlocal next_ip
        if next_ip is None:
            die("内部错误: 未设置起始 IP")
        while True:
            cand = ipaddress.ip_address(next_ip)
            next_ip += 1
            if cand not in net:
                die(f"IP 分配超出网段 {net} (需要更多地址，请检查 --ip-start/--network)")
            if cand == net.network_address or cand == net.broadcast_address:
                continue
            s = str(cand)
            if s in used:
                continue
            used[s] = desc
            return s

    for role, count in plan:
        short = ROLE_DEFAULTS[role]["short"]
        for _ in range(count):
            counters[role] = counters.get(role, 0) + 1
            idx = counters[role]
            label = f"{role}#{idx}"
            ip = alloc_ip(label)

            # vm_name 里的 IP 段沿用项目约定: 取后两段, 如 [222.201]
            octets = ip.split(".")
            ip_tag = f"{octets[-2]}.{octets[-1]}" if len(octets) >= 2 else ip
            vm_name = f"{args.vm_name_prefix}-{short}{idx:02d}[{ip_tag}]-{args.date}"
            fqdn = f"{args.cluster_name}-{short}-{idx:02d}"

            nodes.append({
                "role": role,
                "vm_name": vm_name,
                "fqdn": fqdn,
                "ip": f"{ip}/{net.prefixlen}",
                "gateway": args.gateway_ip,
                "nameservers": list(args.nameservers),
                "cpu": None, "memory": None, "disk_size": None,
                "addl_disks": [],
            })
    return nodes


def apply_spec(nodes: list[dict], spec: dict, args) -> list[dict]:
    """用 spec 文件覆盖/追加节点定义 (精确 IP / 规格 场景)。"""
    spec_nodes = spec.get("virtual_machines")
    if not spec_nodes:
        return nodes
    if args.masters or args.workers or args.registry or args.gateway or args.extra:
        die("--spec 与 --masters/--workers/... 不能同时使用 (避免语义冲突)")

    out: list[dict] = []
    for i, n in enumerate(spec_nodes):
        role = n.get("role", "worker")
        if role not in ROLE_DEFAULTS:
            die(f"spec 第 {i+1} 个节点角色 {role!r} 无效")
        out.append({
            "role": role,
            "vm_name": n.get("vm_name") or die(f"spec 第 {i+1} 个节点缺少 vm_name"),
            "fqdn": n.get("fqdn") or die(f"spec 第 {i+1} 个节点缺少 fqdn"),
            "ip": n.get("ip") or die(f"spec 第 {i+1} 个节点缺少 ip"),
            "gateway": n.get("gateway", args.gateway_ip),
            "nameservers": n.get("nameservers", list(args.nameservers)),
            "cpu": n.get("cpu"), "memory": n.get("memory"),
            "disk_size": n.get("disk_size"),
            "addl_disks": n.get("addl_disks", []),
        })

    # 校验 IP 唯一
    seen: dict[str, str] = {}
    for n in out:
        ip = n["ip"].split("/")[0]
        if ip in seen:
            die(f"spec 中 IP 重复: {ip} ({seen[ip]} 与 {n['vm_name']})")
        seen[ip] = n["vm_name"]
    return out


def apply_overrides(nodes: list[dict], args) -> None:
    """把角色级规格参数写到对应节点上 (None 表示沿用 locals.tf 的 role 默认值)。"""
    per_role = {
        "control-plane": (args.master_cpu, args.master_mem, args.master_disk, args.master_data_disk),
        "worker":        (args.worker_cpu, args.worker_mem, args.worker_disk, args.worker_data_disk),
        "registry":      (args.registry_cpu, args.registry_mem, args.registry_disk, args.registry_data_disk),
        "gateway":       (args.gateway_cpu, args.gateway_mem, args.gateway_disk, args.gateway_data_disk),
    }
    for n in nodes:
        cpu, mem, disk, data = per_role[n["role"]]
        n["cpu"], n["memory"], n["disk_size"] = cpu, mem, disk
        if data and data > 0:
            n["addl_disks"] = [{"label": "disk1", "size": data, "unit_number": 1}]


def validate(nodes: list[dict]) -> None:
    ips: dict[str, str] = {}
    for n in nodes:
        raw = n["ip"].split("/")[0]
        if raw in ips:
            die(f"IP 冲突: {raw} 同时分配给 {ips[raw]} 和 {n['vm_name']}")
        ips[raw] = n["vm_name"]
    for n in nodes:
        if not n["fqdn"] or not n["vm_name"]:
            die("主机名/vm_name 不能为空")


# --------------------------------------------------------------------------- #
# 渲染 tfvars
# --------------------------------------------------------------------------- #

def hcl_str(s: str) -> str:
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def render_tfvars(nodes, args, ssh_keys, password) -> str:
    L: list[str] = []
    A = L.append

    A("# =============================================================================")
    A("# 由 terraform.py 自动生成 — 请勿手工编辑 (改参数后重新生成)")
    A(f"# 生成时间: {date.today().isoformat()}")
    A(f"# 拓扑: {len(nodes)} 台 " +
      ", ".join(f"{r}×{sum(1 for n in nodes if n['role'] == r)}"
                for r in dict.fromkeys(n["role"] for n in nodes)))
    A("# =============================================================================")
    A("")

    A("# --- vCenter 连接 ---")
    A("# 建议改用环境变量注入凭据: export TF_VAR_vsphere_password='...'")
    A(f"vsphere_user       = {hcl_str(args.vsphere_user)}")
    A(f"vsphere_password   = {hcl_str(args.vsphere_password)}")
    A(f"vsphere_server     = {hcl_str(args.vsphere_server)}")
    A(f"vsphere_datacenter = {hcl_str(args.datacenter)}")
    A(f"vsphere_host       = {hcl_str(args.esxi_host)}")
    A(f"vsphere_datastore  = {hcl_str(args.datastore)}")
    A(f"vsphere_network    = {hcl_str(args.vm_network)}")
    A("")

    A("# --- 模板与账号 ---")
    A(f"vm_template_name = {hcl_str(args.template)}")
    A(f"vm_user          = {hcl_str(args.vm_user)}")
    A(f"vm_group         = {hcl_str(args.vm_group)}")
    A(f"vm_timezone      = {hcl_str(args.timezone)}")
    A("ssh_authorized_keys = [")
    for k in ssh_keys:
        A(f"  {hcl_str(k)},")
    A("]")
    if password:
        A("")
        A("# 密码认证 (留空则仅密钥登录; 需同时设置 enable_password_auth = true)")
        A(f"vm_password           = {hcl_str(password)}")
        A(f"enable_password_auth  = {'true' if args.enable_password_auth else 'false'}")
    A("")

    A("# --- Kubernetes 版本 (联动 apt 源 / sandbox 镜像 / crictl, 见 locals.tf) ---")
    A(f"k8s_version = {hcl_str(args.k8s_version)}")
    A(f"cni_plugin  = {hcl_str(args.cni)}")
    A("")

    A("# --- cloud-init 模板 ---")
    A("# userdata-v2.tftpl 支持 %{if nerdctl} 等条件开关 + 镜像仓库配置")
    A(f"userdata_file = {hcl_str(args.userdata_file)}")
    A("")

    A("# --- VM 特性开关 (对应模板里的 %{if ...}) ---")
    A("vm_features = {")
    A(f"  nerdctl         = {str(args.feature_nerdctl).lower()}")
    A(f"  docker_ce       = {str(args.feature_docker_ce).lower()}")
    A(f"  helm            = {str(args.feature_helm).lower()}")
    A(f"  k9s             = {str(args.feature_k9s).lower()}")
    A(f"  bash_completion = {str(args.feature_bash_completion).lower()}")
    A(f"  motd            = {str(args.feature_motd).lower()}")
    A("}")
    A("")

    A("# --- 镜像仓库 (Harbor) ---")
    A("harbor = {")
    A(f"  enabled = {str(args.harbor_enabled).lower()}")
    A(f"  host    = {hcl_str(args.harbor_host)}")
    A(f"  ip      = {hcl_str(args.harbor_ip)}")
    A("}")
    A("")

    A("# --- VM 定义 (规格留空则由 role 默认值决定, 见 locals.tf role_defaults) ---")
    A("virtual_machines = [")
    for n in nodes:
        A("  {")
        A(f"    vm_name     = {hcl_str(n['vm_name'])}")
        A(f"    fqdn        = {hcl_str(n['fqdn'])}")
        A(f"    ip          = {hcl_str(n['ip'])}")
        A(f"    gateway     = {hcl_str(n['gateway'])}")
        ns = ", ".join(hcl_str(x) for x in n["nameservers"])
        A(f"    nameservers = [{ns}]")
        A(f"    role        = {hcl_str(n['role'])}")
        if n["cpu"]:
            A(f"    cpu         = {n['cpu']}")
        if n["memory"]:
            A(f"    memory      = {n['memory']}")
        if n["disk_size"]:
            A(f"    disk_size   = {n['disk_size']}")
        if n["addl_disks"]:
            disks = ", ".join(
                "{ label = %s, size = %s, unit_number = %s }"
                % (hcl_str(d["label"]), d["size"], d["unit_number"])
                for d in n["addl_disks"]
            )
            A(f"    addl_disks  = [{disks}]")
        A("  },")
    A("]")
    A("")
    return "\n".join(L)


def print_summary(nodes, args) -> None:
    print()
    print(f"  拓扑: {args.cluster_name}  |  K8s {args.k8s_version}  |  CNI {args.cni}")
    print("  " + "-" * 88)
    print(f"  {'角色':<14}{'主机名 (fqdn)':<32}{'IP':<18}{'规格 (CPU/内存/盘)':<22}")
    print("  " + "-" * 88)
    for n in nodes:
        spec = f"{n['cpu'] or '默认'}/{n['memory'] or '默认'}/{n['disk_size'] or '默认'}"
        if n["addl_disks"]:
            spec += f" +{n['addl_disks'][0]['size']}G"
        print(f"  {n['role']:<14}{n['fqdn']:<32}{n['ip']:<18}{spec:<22}")
    print("  " + "-" * 88)
    print(f"  合计 {len(nodes)} 台")
    print()


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="terraform.py",
        description="生成 Kubernetes 集群的 Terraform tfvars",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="示例:\n"
               "  ./terraform.py --masters 1 --workers 5 --cni calico --dry-run\n"
               "  ./terraform.py --masters 1 --workers 3 --registry 1 "
               "--password 'Str0ng!Pass' --output examples/kubernetes/terraform.tfvars\n",
    )

    g = p.add_argument_group("拓扑与数量")
    # 默认值留 None: 以便区分「用户显式指定」与「未指定」,
    # 从而让 --spec 不与默认数量冲突 (默认拓扑在 main() 里补)
    g.add_argument("--masters", type=int, default=None, help="控制平面数量 (默认 1)")
    g.add_argument("--workers", type=int, default=None, help="工作节点数量 (默认 3)")
    g.add_argument("--registry", type=int, default=None, help="Harbor 镜像仓库节点数 (默认 1, 0=不要)")
    g.add_argument("--gateway", type=int, default=None, help="网关/OpenWrt 节点数 (默认 0)")
    g.add_argument("--extra", action="append", metavar="ROLE:COUNT",
                   help="追加任意角色节点, 可重复, 如 --extra worker:5")
    g.add_argument("--spec", help="从 JSON/YAML 拓扑文件读取 (与数量参数互斥)")

    g2 = p.add_argument_group("命名")
    g2.add_argument("--cluster-name", default="test-cjl-k8s01", help="集群名 (用于 fqdn 前缀)")
    g2.add_argument("--vm-name-prefix", default="k8s01", help="vSphere 显示名前缀")
    g2.add_argument("--date", default=date.today().strftime("%Y%m%d"), help="命名中的日期段")

    g3 = p.add_argument_group("网络与 IP")
    g3.add_argument("--network", default="172.16.222.0/24", help="网段 CIDR")
    g3.add_argument("--ip-start", default="172.16.222.201", help="起始 IP, 按顺序分配")
    g3.add_argument("--default-gateway", dest="gateway_ip", default=None,
                    help="默认网关地址 (默认取网段 .254)")
    g3.add_argument("--nameservers", default=",".join(DEFAULT_NAMESERVERS),
                    help="DNS 列表, 逗号分隔")

    g4 = p.add_argument_group("规格 (留空则用 locals.tf 的 role 默认值)")
    for role, flag in (("master", "control-plane"), ("worker", "worker"),
                       ("registry", "registry"), ("gateway", "gateway")):
        g4.add_argument(f"--{role}-cpu", type=int, default=None)
        g4.add_argument(f"--{role}-mem", type=int, default=None, help="内存 MB")
        g4.add_argument(f"--{role}-disk", type=int, default=None, help="系统盘 GB")
        g4.add_argument(f"--{role}-data-disk", type=int, default=None, help="数据盘 GB")

    g5 = p.add_argument_group("凭据")
    g5.add_argument("--password", default=None, help="VM 登录密码 (写入 tfvars)")
    g5.add_argument("--generate-password", action="store_true", help="自动生成强口令")
    g5.add_argument("--enable-password-auth", action="store_true",
                    help="同时开启 ssh 密码认证 (默认仅密钥)")
    g5.add_argument("--ssh-key-file", action="append", metavar="PATH",
                    help="SSH 公钥文件, 可重复")
    g5.add_argument("--ssh-key", action="append", metavar="KEY",
                    help="内联 SSH 公钥, 可重复")

    g6 = p.add_argument_group("K8s 与组件")
    g6.add_argument("--k8s-version", default="v1.36", choices=K8S_VERSIONS)
    g6.add_argument("--cni", default="cilium", choices=CNI_CHOICES,
                    help="Kubernetes 网络插件")
    g6.add_argument("--userdata-file", default="examples/kubernetes/userdata-v2.tftpl")

    g7 = p.add_argument_group("VM 特性开关")
    for name, default, helptext in (
        ("nerdctl", True, "安装 nerdctl"),
        ("docker-ce", False, "安装 docker-ce"),
        ("helm", True, "安装 helm"),
        ("k9s", False, "安装 k9s"),
        ("bash-completion", True, "安装 bash 补全"),
        ("motd", True, "写入 GZD Cloud 欢迎信息"),
    ):
        g7.add_argument(f"--no-{name}" if default else f"--{name}",
                        dest=f"feature_{name.replace('-', '_')}",
                        action="store_false" if default else "store_true",
                        default=default, help=helptext)

    g8 = p.add_argument_group("镜像仓库")
    g8.add_argument("--harbor-host", default="harbor.yjscloud.local")
    g8.add_argument("--harbor-ip", default="172.16.222.207")
    g8.add_argument("--no-harbor", dest="harbor_enabled", action="store_false",
                    default=True, help="不配置镜像仓库代理")

    g9 = p.add_argument_group("vCenter / ESXi")
    g9.add_argument("--vsphere-user", default="CHANGE_ME_USER")
    g9.add_argument("--vsphere-password", default="CHANGE_ME_OR_USE_TF_VAR")
    g9.add_argument("--vsphere-server", default="172.16.222.240")
    g9.add_argument("--datacenter", default="CJL")
    g9.add_argument("--esxi-host", default="172.16.222.243")
    g9.add_argument("--datastore", default="date01")
    g9.add_argument("--vm-network", default="VM Network")
    g9.add_argument("--template", default="ubuntu-noble-24.04-cloudimg-20260826")
    g9.add_argument("--vm-user", default="appuser")
    g9.add_argument("--vm-group", default="appowner")
    g9.add_argument("--timezone", default="Asia/Shanghai")

    g10 = p.add_argument_group("输出")
    g10.add_argument("--output", default="examples/kubernetes/terraform.tfvars",
                     help="输出路径 (默认 examples/kubernetes/terraform.tfvars)")
    g10.add_argument("--dry-run", action="store_true", help="只打印不写文件")
    return p


def load_spec(path: str) -> dict:
    p = Path(norm_path(path))
    if not p.is_file():
        die(f"spec 文件不存在: {path}")
    text = p.read_text(encoding="utf-8")
    if p.suffix.lower() in (".yaml", ".yml"):
        try:
            import yaml  # type: ignore
        except ImportError:
            die("读取 YAML 需要 PyYAML: pip install pyyaml (或改用 .json)")
        return yaml.safe_load(text)
    return json.loads(text)


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    # --default-gateway 缺省时取广播地址前一个 (常规网关位, /24 即 .254)
    if args.gateway_ip is None:
        net = ipaddress.ip_network(args.network, strict=False)
        args.gateway_ip = str(net.broadcast_address - 1)
    args.nameservers = [s.strip() for s in args.nameservers.split(",") if s.strip()]

    # 拓扑
    if args.spec:
        nodes = apply_spec([], load_spec(args.spec), args)
    else:
        # 未显式指定数量时套用默认拓扑 (1 控制面 + 3 worker + 1 registry)
        if args.masters is None:
            args.masters = 1
        if args.workers is None:
            args.workers = 3
        if args.registry is None:
            args.registry = 1
        if args.gateway is None:
            args.gateway = 0
        nodes = build_nodes(args)
    apply_overrides(nodes, args)
    validate(nodes)

    # 凭据
    ssh_keys = read_ssh_keys(args.ssh_key_file, args.ssh_key)
    password = args.password
    if args.generate_password:
        password = gen_password()
        print(f"[INFO] 已生成密码: {password}")
        print("[INFO] 请妥善保存 — 该密码同时写入 tfvars 与 cloud-init")
    if password and not args.enable_password_auth:
        print("[WARN] 提供了 --password 但未加 --enable-password-auth，"
              "VM 仍将只允许密钥登录 (密码仅作备用/应急)。", file=sys.stderr)

    print_summary(nodes, args)
    content = render_tfvars(nodes, args, ssh_keys, password)

    if args.dry_run:
        print("=== DRY RUN — 以下内容不会写入文件 ===")
        print(content)
        return 0

    out = Path(norm_path(args.output))
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        backup = out.with_suffix(out.suffix + ".bak")
        backup.write_text(out.read_text(encoding="utf-8"), encoding="utf-8")
        print(f"[INFO] 已备份原文件到 {backup}")
    out.write_text(content, encoding="utf-8")
    print(f"[OK] 已写入 {out}  ({len(content)} 字节)")
    print(f"[NEXT] terraform plan -var-file={out}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n[中断]", file=sys.stderr)
        sys.exit(130)
