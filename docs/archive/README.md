# docs/archive — 历史文档归档

本目录保存项目重构（2026-09）前的旧文档、旧脚本与旧模板，**仅供追溯，
描述的目录结构与流程已过时**（如 `terraform.py`、根目录 main.tf、Shell 编排等）。

现行文档见 `docs/00-overview.md` 至 `docs/19-troubleshooting.md`。

| 归档内容 | 说明 |
|---|---|
| `00-架构与规划.md` ~ `TIMELINE.md` | 旧版项目文档（test-cjl-k8s01 首次部署全程记录） |
| `legacy-kubernetes/` | 旧 examples/kubernetes（userdata 模板、tfvars、vm-specs 预设） |
| `legacy-scripts/` | 旧部署脚本（lib/00-env.sh、k8s/harbor/openwrt 阶段脚本、terraform.py） |

有价值的踩坑结论已收编进新文档：
- containerd config_path 单路径问题 → `docs/19-troubleshooting.md`
- Harbor proxy cache / TLS → `docs/12-harbor.md`
- OpenWrt DNS 幂等陷阱 → `docs/11-openwrt.md`
- kubeadm init/join 实测命令 → `docs/09-kubernetes.md`
