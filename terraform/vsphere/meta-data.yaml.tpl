# =============================================================================
# meta-data.yaml.tpl — cloud-init 元数据 + 静态网络配置 (v2 格式)
#
# 由 Terraform 注入 VM 的 guestinfo.metadata (base64)。
# VMware cloud-init 数据源从 metadata 的 network 键读取网络配置。
# =============================================================================
instance-id: ${hostname}
local-hostname: ${hostname}

network:
  version: 2
  ethernets:
    ${interface}:
      addresses:
        - ${ip}
      gateway4: ${gateway}
      nameservers:
        addresses:
          %{~ for ns in dns ~}
          - ${ns}
          %{~ endfor ~}
