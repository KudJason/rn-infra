# GCP Minimal Infrastructure (GKE Autopilot)

本 Terraform 栈创建最小可运行的基础设施：
- VPC / 子网（含 Pods/Services 二级网段）
- Cloud NAT（私有出站）
- Artifact Registry（Docker 仓库）
- GKE Autopilot 集群（REGULAR 渠道，Workload Identity 已启用）

先决条件：
- 已完成 `gcloud auth login --update-adc` 且 `gcloud config set project` 指向目标项目
- 已创建 GCS 远端状态桶（仓库脚本已创建 `gs://tf-state-rural-neighbor-477211`）

使用：
```bash
cd infra/terraform/gcp-minimal-gke
terraform init
terraform apply
```

应用后：
```bash
# 获取集群凭据
gcloud container clusters get-credentials rn-autopilot-minimal --region us-east4

# 之后使用现有 k8s 清单部署（示例）
kubectl apply -k /Users/jasonjia/Documents/codebase/ruralneighbour/ms-backend/k8s/overlays/staging
```

说明：
- 此模板不创建数据库或 Redis（保留由现有 k8s StatefulSet/Deployment 管理，最小化依赖）。如需托管版，可扩展：Cloud SQL（PostgreSQL+PostGIS）与 Memorystore Redis。
- 建议将镜像推送到 Artifact Registry：`us-east4-docker.pkg.dev/<PROJECT_ID>/rn-backend/<image>:<tag>`。


