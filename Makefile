# =============================================================================
# iac-k8s-esxi — 薄封装入口 (核心入口是 terraform/vsphere/)
#
#   make generate            # cluster.yaml → vm.tf
#   make init/plan/apply/destroy
#   make fmt / validate
#
# 也可以直接: cd terraform/vsphere && python generate.py && terraform apply
# =============================================================================
TF_DIR := terraform/vsphere

.DEFAULT_GOAL := help
.PHONY: help generate init fmt validate plan apply destroy docs

help:
	@echo "iac-k8s-esxi — vSphere Kubernetes IaC"
	@echo
	@echo "  make generate      生成节点定义 (terraform/vsphere/cluster.yaml -> vm.tf)"
	@echo "  make init          terraform init"
	@echo "  make plan          terraform plan"
	@echo "  make apply         terraform apply"
	@echo "  make destroy       terraform destroy (危险: 删除全部节点 VM)"
	@echo "  make fmt           terraform fmt -recursive"
	@echo "  make validate      terraform validate"
	@echo "  make docs          启动知识库站点 (Docusaurus, http://localhost:3000)"
	@echo
	@echo "集群引导: docs/02-Kubernetes/   平台扩展: k8s-plugins/   知识库: docs/ + website/"

generate:
	cd $(TF_DIR) && python generate.py

init:
	terraform -chdir=$(TF_DIR) init

fmt:
	terraform -chdir=$(TF_DIR) fmt -recursive

validate: fmt
	terraform -chdir=$(TF_DIR) validate

plan:
	terraform -chdir=$(TF_DIR) plan

apply:
	terraform -chdir=$(TF_DIR) apply

destroy:
	terraform -chdir=$(TF_DIR) destroy

# 知识库站点 (Docusaurus, 首次运行需先: cd website && npm install)
docs:
	cd website && npm run start
