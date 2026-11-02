#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
generate.py — Kubernetes Node Generator (本项目 Python 的唯一职责)

读取 cluster.yaml → 计算节点 (数量/规格/IP/主机名) → 生成/更新 vm.tf

数据流:
    cluster.yaml (用户编辑)
        ↓ python generate.py
    vm.tf (locals: cluster + nodes, resource 用 for_each)
        ↓ terraform plan / apply
    vSphere VM × N → Cloud-Init → kubeadm-ready

职责边界:
    - 只生成参数与 VM 定义, 不执行 terraform 命令
    - 不为每个节点生成独立 .tf (一个 vm.tf + for_each)
    - 不管 kubeadm init/join (docs/02-Kubernetes/), 不管插件 (k8s-plugins/)

用法:
    python generate.py               # 读 ./cluster.yaml → 写 ./vm.tf
    python generate.py --config x.yaml
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import sys
from datetime import date, datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent

# K8s 版本联动目录 (单一真值源): pause 版本须与该版本 kubeadm 期望一致,
# crictl 与 K8s 版本相差不超过 1 个 minor (官方兼容矩阵)
K8S_CATALOG = {
    "1.33": {"pause": "3.10", "crictl": "v1.33.0"},
    "1.34": {"pause": "3.10", "crictl": "v1.34.0"},
    "1.35": {"pause": "3.10", "crictl": "v1.35.0"},
    "1.36": {"pause": "3.10.1", "crictl": "v1.33.0"},
    "1.37": {"pause": "3.11", "crictl": "v1.34.0"},
}

ROLE_SHORT = {"master": "master", "worker": "worker"}


def die(msg: str, code: int = 2) -> None:
    print(f"[ERROR] {msg}", file=sys.stderr)
    sys.exit(code)


def warn(msg: str) -> None:
    print(f"[WARN] {msg}", file=sys.stderr)


# --------------------------------------------------------------------------- #
# 配置
# --------------------------------------------------------------------------- #

def load_config(path: Path) -> dict:
    try:
        import yaml  # type: ignore
    except ImportError:
        die("缺少 PyYAML: pip install pyyaml")
    if not path.is_file():
        die(f"配置文件不存在: {path}")
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def resolve_ssh_keys(cfg: dict) -> list[str]:
    ssh_cfg = cfg.get("ssh") or {}
    candidates: list[Path] = []
    if ssh_cfg.get("public_key_file"):
        candidates.append(Path(str(ssh_cfg["public_key_file"])).expanduser())
    else:
        candidates += [Path.home() / ".ssh" / "id_ed25519.pub",
                       Path.home() / ".ssh" / "id_rsa.pub"]
    for p in candidates:
        if p.is_file() and p.read_text(encoding="utf-8").strip():
            keys = [ln.strip() for ln in p.read_text(encoding="utf-8").splitlines()
                    if ln.strip() and not ln.strip().startswith("#")]
            if keys:
                print(f"[INFO] SSH 公钥: {p}")
                return keys
    die("未找到 SSH 公钥 (查找: " + ", ".join(str(c) for c in candidates) + ")\n"
        "       请先 ssh-keygen -t ed25519, 或在 cluster.yaml 的 ssh.public_key_file 指定")


# --------------------------------------------------------------------------- #
# 节点计算
# --------------------------------------------------------------------------- #

def build_nodes(cfg: dict) -> tuple[list[dict], str]:
    network = cfg["network"]
    net = ipaddress.ip_network(network["cidr"], strict=False)
    gateway = network["gateway"]
    if ipaddress.ip_address(gateway) not in net:
        die(f"网关 {gateway} 不在网段 {net} 内")
    dns = list(network.get("dns") or [])
    if not dns:
        die("network.dns 不能为空")

    date_tag = str(network.get("date") or "auto")
    if date_tag.lower() == "auto":
        date_tag = date.today().strftime("%Y%m%d")

    used: dict[str, str] = {gateway: "gateway"}
    cursor = int(ipaddress.ip_address(network["ip_start"]))

    def alloc_ip(desc: str, explicit: str | None) -> str:
        nonlocal cursor
        if explicit:
            ip = str(ipaddress.ip_address(explicit))
            if ip not in net or ip in (str(net.network_address), str(net.broadcast_address)):
                die(f"显式 IP {explicit} ({desc}) 不在可用网段 {net} 内")
            if ip in used:
                die(f"IP 冲突: {ip} 已分配给 {used[ip]}, 无法再分配给 {desc}")
            used[ip] = desc
            return ip
        while True:
            cand = ipaddress.ip_address(cursor)
            cursor += 1
            s = str(cand)
            if cand not in net:
                die(f"IP 分配超出网段 {net}: 调整 network.ip_start 或改用显式 IP")
            if s in used:
                continue
            used[s] = desc
            return s

    cluster = cfg["cluster"]
    nodes: list[dict] = []
    for role in ("master", "worker"):
        rc = cfg[f"{role}s"]
        count = int(rc["count"])
        if role == "master" and count > 1 and count % 2 == 0:
            warn(f"master 数量为 {count}, etcd 建议奇数 (1/3/5)")
        explicit_ips = list(rc.get("ips") or [])
        if explicit_ips and len(explicit_ips) != count:
            die(f"{role}.ips 数量 ({len(explicit_ips)}) 与 {role}.count ({count}) 不一致")
        for i in range(1, count + 1):
            # 命名规范集中在 generate.py (勿在其它文件重复硬编码):
            #   hostname: <environment>-<location>-<cluster>-<role>-<NN>
            #   vm_name:  <cluster>-<role><NN>[<IP后两段>]-<date>
            hostname = f"{cluster['environment']}-{cluster['location']}-{cluster['id']}-{role}-{i:02d}"
            ip = alloc_ip(f"{role}-{i:02d}", explicit_ips[i - 1] if explicit_ips else None)
            octets = ip.split(".")
            ip_tag = f"{octets[-2]}.{octets[-1]}"
            nodes.append({
                "hostname": hostname,
                "vm_name": f"{cluster['id']}-{ROLE_SHORT[role]}{i:02d}[{ip_tag}]-{date_tag}",
                "role": role,
                "index": i,
                "ip": f"{ip}/{net.prefixlen}",
                "gateway": gateway,
                "nameservers": list(dns),
                "cpu": int(rc["cpu"]),
                "memory": int(rc["memory"]),
                "disk": int(rc["disk"]),
                "data_disks": ([{"label": "disk1", "size": int(rc["data_disk"]), "unit": 1}]
                               if int(rc.get("data_disk") or 0) > 0 else []),
            })

    if not nodes:
        die("至少需要一个节点 (masters.count + workers.count > 0)")
    return nodes, date_tag


def build_cluster_block(cfg: dict) -> dict:
    k8s = cfg["kubernetes"]
    version = str(k8s["version"])
    if version not in K8S_CATALOG:
        die(f"kubernetes.version={version} 不受支持, 可选: {', '.join(K8S_CATALOG)}")
    cat = K8S_CATALOG[version]
    tools = cfg.get("tools") or {}
    harbor = cfg.get("harbor") or {}
    return {
        "name": cfg["cluster"]["name"],
        "environment": cfg["cluster"]["environment"],
        "location": cfg["cluster"]["location"],
        "id": cfg["cluster"]["id"],
        "network_interface": cfg["network"].get("interface") or "ens192",
        "user": cfg["os"]["user"],
        "group": cfg["os"]["group"],
        "timezone": cfg["os"]["timezone"],
        "apt_mirror": cfg["os"].get("apt_mirror") or "",
        "apt_suite": cfg["os"].get("apt_suite") or "noble",
        "ntp_servers": list(cfg["os"].get("ntp") or []),
        "ssh_authorized_keys": resolve_ssh_keys(cfg),
        "enable_password_auth": bool((cfg.get("ssh") or {}).get("enable_password_auth")),
        "vm_password": str((cfg.get("ssh") or {}).get("vm_password") or ""),
        "k8s_version": version,
        "k8s_apt_repo": str(k8s["apt_repo"]).format(version=version),
        "k8s_pause_image": f"{str(k8s['pause_registry']).rstrip('/')}/pause:{cat['pause']}",
        "crictl_version": cat["crictl"],
        "cni_plugin": str(k8s.get("cni_plugin") or "cilium"),
        "pod_cidr": k8s["pod_cidr"],
        "service_cidr": k8s["service_cidr"],
        "helm_enabled": bool(tools.get("helm", {}).get("enabled", True)),
        "helm_url": tools.get("helm", {}).get("url", ""),
        "nerdctl_enabled": bool(tools.get("nerdctl", {}).get("enabled", True)),
        "nerdctl_url": tools.get("nerdctl", {}).get("url", ""),
        "bash_completion": bool(tools.get("bash_completion", True)),
        "harbor_enabled": bool(harbor.get("enabled")),
        "harbor_host": str(harbor.get("host") or ""),
        "harbor_ip": str(harbor.get("ip") or ""),
        "harbor_upstreams": {str(k): str(v) for k, v in (harbor.get("upstreams") or {}).items()},
    }


# --------------------------------------------------------------------------- #
# vm.tf 生成
# --------------------------------------------------------------------------- #

VM_TF_TEMPLATE = """# =============================================================================
# vm.tf — K8s 节点 VM 定义 (由 generate.py 自动生成, 勿手工编辑)
#
# 数据来源: cluster.yaml (改配置后重新执行 python generate.py)
# 结构: locals (cluster + nodes) + 一个 for_each 资源管理所有节点
# 生成时间: {generated_at}
# =============================================================================

locals {{
  # 集群级参数 (来源: cluster.yaml)
  cluster = {cluster}

  # 节点集合: 键 = Linux 主机名 (稳定, 与 terraform state 对应)
  nodes = {nodes}
}}

# ---------------------------------------------------------------------------
# 所有 K8s 节点 (master + worker) 由本资源批量管理, 禁止为单节点创建独立 .tf
# ---------------------------------------------------------------------------
resource "vsphere_virtual_machine" "k8s_node" {{
  for_each = local.nodes

  # vSphere 显示名, 如 k8s01-master01[222.201]-20260907
  name                       = each.value.vm_name
  resource_pool_id           = data.vsphere_host.this.resource_pool_id
  datastore_id               = data.vsphere_datastore.this.id
  num_cpus                   = each.value.cpu
  memory                     = each.value.memory
  guest_id                   = data.vsphere_virtual_machine.template.guest_id
  scsi_type                  = data.vsphere_virtual_machine.template.scsi_type
  wait_for_guest_net_timeout = 0

  cdrom {{
    client_device = true
  }}

  network_interface {{
    network_id   = data.vsphere_network.this.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }}

  # 系统盘 (置备参数沿用模板)
  disk {{
    label            = "disk0"
    size             = each.value.disk
    eagerly_scrub    = data.vsphere_virtual_machine.template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
  }}

  # 附加数据盘 (如 Longhorn 数据盘), 由 cluster.yaml 按角色生成
  dynamic "disk" {{
    for_each = each.value.data_disks
    content {{
      label            = disk.value.label
      size             = disk.value.size
      eagerly_scrub    = false
      thin_provisioned = true
      unit_number      = disk.value.unit
    }}
  }}

  clone {{
    template_uuid = data.vsphere_virtual_machine.template.id
  }}

  # cloud-init via guestinfo (模板需 cloud-init >= 21.3)
  # metadata: 实例 ID + 静态网络;  userdata: OS 初始化 (见 user-data.yaml.tpl)
  extra_config = {{
    "guestinfo.metadata" = base64encode(templatefile("${{path.module}}/meta-data.yaml.tpl", {{
      hostname  = each.key
      interface = local.cluster.network_interface
      ip        = each.value.ip
      gateway   = each.value.gateway
      dns       = each.value.nameservers
    }}))
    "guestinfo.metadata.encoding" = "base64"
    "guestinfo.userdata" = base64encode(templatefile("${{path.module}}/user-data.yaml.tpl",
      merge(local.userdata_common, {{
        hostname   = each.key
        role       = each.value.role
        data_disks = each.value.data_disks
    }})))
    "guestinfo.userdata.encoding" = "base64"
  }}

  lifecycle {{
    # vm_name 含日期段; 改名不要通过 Terraform (避免销毁重建)
    ignore_changes = [name]
  }}
}}
"""


def _hcl_key(k: str) -> str:
    """合法标识符裸写, 其余加引号 (HCL object 键规则)。"""
    import re
    return k if re.fullmatch(r"[a-z_][a-z0-9_]*", k) else json.dumps(k, ensure_ascii=False)


def hcl(value, indent: int = 0) -> str:
    """Python 值 → terraform fmt 风格的多行 HCL (键对齐/缩进/引号键)。"""
    pad = " " * indent
    if isinstance(value, dict):
        if not value:
            return "{}"
        keys = [(k, _hcl_key(k)) for k in value]
        width = max(len(rendered) for _, rendered in keys)
        lines = ["{"]
        for k, rendered in keys:
            v = hcl(value[k], indent + 2)
            key_col = rendered.ljust(width) if "\n" not in v else rendered
            lines.append(f"{' ' * (indent + 2)}{key_col} = {v}")
        lines.append(f"{pad}}}")
        return "\n".join(lines)
    if isinstance(value, list):
        if not value:
            return "[]"
        if all(isinstance(x, (str, int, float, bool)) for x in value):
            return "[" + ", ".join(hcl(x) for x in value) + "]"
        lines = ["["]
        for x in value:
            lines.append(f"{' ' * (indent + 2)}{hcl(x, indent + 2)},")
        lines.append(f"{pad}]")
        return "\n".join(lines)
    return json.dumps(value, ensure_ascii=False)


def render_vm_tf(cluster: dict, nodes: list[dict]) -> str:
    nodes_map = {n["hostname"]: {k: v for k, v in n.items() if k != "hostname"}
                 for n in nodes}
    body = {
        "cluster": cluster,
        "nodes": nodes_map,
    }
    return VM_TF_TEMPLATE.format(
        generated_at=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        cluster=hcl(cluster, 2),
        nodes=hcl(nodes_map, 2),
    )


# --------------------------------------------------------------------------- #
# 摘要输出
# --------------------------------------------------------------------------- #

def print_summary(cluster: dict, nodes: list[dict]) -> None:
    masters = [n for n in nodes if n["role"] == "master"]
    workers = [n for n in nodes if n["role"] == "worker"]
    print()
    print("Generated Kubernetes Environment:")
    print()
    print(f"Cluster:  {cluster['name']}")
    print(f"Masters:  {len(masters)}")
    print(f"Workers:  {len(workers)}")
    print()
    print("Nodes:")
    for n in nodes:
        dd = f" +{n['data_disks'][0]['size']}G" if n["data_disks"] else ""
        print(f"  {n['hostname']:<36} {n['ip']:<22} "
              f"{n['cpu']}C/{n['memory']}M/{n['disk']}G{dd}")
    print()
    print(f"K8s:      {cluster['k8s_version']}  (pause: {cluster['k8s_pause_image']})")
    print("Generated: terraform/vsphere/vm.tf")
    print()
    print("Next:")
    print("  terraform init")
    print("  terraform plan")
    print("  terraform apply")
    print()


# --------------------------------------------------------------------------- #

def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="generate.py",
                                description="Kubernetes Node Generator: cluster.yaml → vm.tf")
    p.add_argument("--config", default=str(HERE / "cluster.yaml"),
                   help="集群配置文件 (默认 ./cluster.yaml)")
    args = p.parse_args(argv)

    cfg = load_config(Path(args.config).expanduser())
    nodes, _ = build_nodes(cfg)
    cluster = build_cluster_block(cfg)

    vm_tf = render_vm_tf(cluster, nodes)
    out = HERE / "vm.tf"
    out.write_text(vm_tf, encoding="utf-8")

    print_summary(cluster, nodes)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n[中断]", file=sys.stderr)
        sys.exit(130)
