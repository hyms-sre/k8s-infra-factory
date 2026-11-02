# =============================================================================
# outputs.tf — 部署结果摘要
# =============================================================================

output "cluster_name" {
  description = "Kubernetes 集群名"
  value       = local.cluster.name
}

output "nodes" {
  description = "节点清单 (hostname / role / IP / 规格)"
  value = [
    for host, n in local.nodes : {
      hostname = host
      role     = n.role
      ip       = n.ip
      cpu      = n.cpu
      memory   = n.memory
      disk     = n.disk
    }
  ]
}

output "ssh_commands" {
  description = "各节点 SSH 登录命令 (用户来自 cluster.yaml)"
  value = [
    for host, n in local.nodes : "${host}: ssh ${local.cluster.user}@${n.ip}"
  ]
}
