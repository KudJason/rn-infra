# Infrastructure Orchestration Overview

本文档汇总整个基础设施的 Terraform 栈与部署顺序，**不含** K8s Pod 部署（Pod 部署将在基础设施就绪后单独执行）。

---

## 架构概览

- **GCP**（1 按需 VM + 2 台 Spot MIG + 数据盘/快照 + KMS/Secret Manager + 备份桶）
- **Cloudflare**（DNS A 记录 + 橙云代理 + 基础安全）
- **预算目标**：≈ $80–95/月，三个月 ≈ $240–285（Cloudflare 免费版）

---

## 已完成资源（当前状态）

### GCP 栈：`infra/terraform/gcp-vm-hybrid`
- ✅ API 启用（compute, iam, logging, monitoring, storage, kms, secretmanager）
- ✅ IAM：VM 专用 Service Account + 日志/监控/备份桶权限
- ✅ 备份桶：`rn-backup-rural-neighbor-477211`（版本化，30 天生命周期）
- ✅ 防火墙：
  - 核心 VM 仅开放 SSH(22) 给 `0.0.0.0/0`（建议后续收紧）
  - 核心 VM 80/443 仅开放给 Cloudflare IPv4 段
  - MIG 全拒入站流量
- ✅ 数据盘：50GB pd-standard + 每日快照（保留 7 天）
- ✅ 核心 VM：`rn-core-vm`（e2-medium，us-east4-a）
  - 公网 IP: `34.48.255.154`
  - 启动脚本：安装 Docker/gcloud，挂载 /data，配置 nightly 备份脚本
- ✅ Spot MIG：`rn-spot-mig`（目标 2 台 e2-medium）
- ✅ KMS：`rn-keyring/app-config`（30 天轮换，CMEK）
- ✅ Secret Manager：
  - `db-password`（CMEK，VM SA 可读）
  - `jwt-secret`（CMEK，VM SA 可读）
  - **注意**：密钥值需手动添加（见下方"待完成"）

### Cloudflare 栈：`infra/terraform/cloudflare`
- ⏸️ DNS 记录：`api.ruralneighbor.com` → `34.48.255.154`（橙云代理）
  - **状态**：待删除现有 CNAME 冲突后创建
- ⏸️ 区域设置（强制 HTTPS/最低 TLS 等）：暂简化，可后续补充

---

## 待完成（按顺序）

### 1. Cloudflare DNS（前置依赖）
```bash
cd infra/terraform/cloudflare
export CLOUDFLARE_API_TOKEN="你的token"

# 删除现有 api CNAME（若存在）
ZONE_ID=$(grep 'zone_id' cloudflare.auto.tfvars | cut -d'"' -f2)
RECORD_ID=$(curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=api.ruralneighbor.com" \
  | jq -r '.result[0].id // empty')
if [ -n "$RECORD_ID" ]; then
  curl -s -X DELETE -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}"
fi

# 创建 A 记录
terraform apply -auto-approve
```

### 2. GCP Secret 值填充（一次性）
```bash
export PROJECT_ID=rural-neighbor-477211

# 示例：设置数据库密码（自定义强密码）
echo -n "your_strong_db_password" | gcloud secrets versions add db-password --data-file=- --project $PROJECT_ID

# 示例：设置 JWT 密钥（随机生成）
openssl rand -base64 32 | tr -d '\n' | gcloud secrets versions add jwt-secret --data-file=- --project $PROJECT_ID
```

### 3. 核心 VM 初始化（SSH 登录后）
```bash
# SSH 到核心 VM
ssh <你的账号>@34.48.255.154

# 克隆代码（或 rsync）
sudo mkdir -p /opt/ruralneighbour && sudo chown $USER /opt/ruralneighbour
cd /opt
git clone <你的仓库地址> ruralneighbour

# 拉取 Secret Manager 密钥并生成环境文件（可选，若你想用 Secrets）
cd /opt/ruralneighbour/ms-backend
cat > .env.production <<ENV
POSTGRES_PASSWORD=$(gcloud secrets versions access latest --secret=db-password)
JWT_SECRET=$(gcloud secrets versions access latest --secret=jwt-secret)
POSTGRES_USER=devuser
POSTGRES_DB=ruralneighbor_prod
REDIS_HOST=redis
ENV

# 创建持久化覆盖（将 Postgres/Redis 数据映射到 /data）
cat > docker-compose.override.yaml <<YAML
services:
  postgres:
    volumes:
      - /data/postgres:/var/lib/postgresql/data
  redis:
    volumes:
      - /data/redis:/data
YAML

# 暂不启动容器（等待后续编排）
```

### 4. 验证基础设施就绪
```bash
# 检查 VM
gcloud compute instances list --project rural-neighbor-477211

# 检查 MIG
gcloud compute instance-groups managed list --project rural-neighbor-477211

# 检查备份桶
gsutil ls -p rural-neighbor-477211 | grep backup

# 检查 DNS（需等 Cloudflare 生效，1–5 分钟）
dig api.ruralneighbor.com +short
# 应返回 Cloudflare 代理 IP（非 34.48.255.154）
```

---

## 后续步骤（Pod 部署阶段）

**在基础设施全部就绪且验证通过后**，再执行容器/Pod 部署：

### 选项A：Docker Compose（核心 VM 直接运行）
```bash
ssh <你的账号>@34.48.255.154
cd /opt/ruralneighbour/ms-backend
docker compose -f scripts/deployment/docker-compose.yaml -f docker-compose.override.yaml up -d
```

### 选项B：K8s 部署到 GKE Autopilot（若需要）
- 需先应用 `infra/terraform/gcp-minimal-gke`（单独栈，会创建 GKE 集群）
- 再用 `kubectl apply -k ms-backend/k8s/overlays/staging`

---

## 成本估算（月度）

| 资源              | 规格/用量                  | 单价（粗略）       | 月费      |
|-------------------|---------------------------|------------------|----------|
| 核心 VM（按需）    | e2-medium (2vCPU/4GB)     | ~$0.055/h        | ~$40     |
| Spot MIG (2台)    | e2-medium Spot            | ~$0.018/h × 2    | ~$26     |
| 数据盘            | 50GB pd-standard          | ~$0.04/GB·月     | ~$2      |
| 快照（7 天）      | 按实际增量                | ~$0.026/GB·月    | <$2      |
| 备份桶 + 镜像     | 轻量存储                  | ~$0.02–0.1/GB    | ~$2      |
| 出网带宽          | 轻量                      | 视用量           | ~$5–10   |
| Cloudflare 免费版 | DNS + 橙云代理            | $0               | $0       |
| **合计**          |                           |                  | **$77–$82/月** |
| **三个月**        |                           |                  | **≈ $231–$246** |

---

## 文件结构

```
infra/
├── terraform/
│   ├── gcp-vm-hybrid/       # GCP 混合架构（按需+Spot+数据盘+KMS+Secrets）
│   │   ├── providers.tf
│   │   ├── variables.tf
│   │   ├── services.tf
│   │   ├── network.tf
│   │   ├── iam.tf
│   │   ├── kms.tf
│   │   ├── secrets.tf
│   │   ├── on_demand_vm.tf
│   │   ├── mig.tf
│   │   ├── backup_snapshot.tf
│   │   ├── outputs.tf
│   │   └── DEFINITIONS_AND_RISKS.md
│   ├── cloudflare/          # Cloudflare DNS + 代理
│   │   ├── providers.tf
│   │   ├── variables.tf
│   │   ├── dns_waf.tf
│   │   ├── outputs.tf
│   │   ├── cloudflare.auto.tfvars  # zone_id/account_id（不含 token）
│   │   └── README.md
│   └── gcp-minimal-gke/     # （可选）GKE Autopilot 栈，当前未应用
└── ORCHESTRATION.md         # 本文档
```

---

## 关键注意事项

- **SSH 来源 IP**：核心 VM 的 SSH(22) 当前对全网开放（`0.0.0.0/0`），生产建议限制为办公出口 IP。
- **Cloudflare Token**：不要提交进 git；使用环境变量或 Secret Manager。
- **Secrets 初始化**：首次部署后必须手动向 Secret Manager 添加密钥值，否则应用启动会失败。
- **MIG 自愈**：Spot 被回收后会自动补齐，但无健康检查；如需高级自愈可加 autohealer。
- **备份验证**：定期测试从快照/GCS 恢复数据的流程。

---

## 快速命令汇总

```bash
# 1. 完成 Cloudflare DNS
cd infra/terraform/cloudflare
export CLOUDFLARE_API_TOKEN="..."
# 删除冲突 + 创建（见"待完成"第1步）
terraform apply

# 2. 填充 GCP Secrets
echo -n "db_pass" | gcloud secrets versions add db-password --data-file=-
echo -n "jwt_key" | gcloud secrets versions add jwt-secret --data-file=-

# 3. SSH 到 VM 并准备环境（不启动 Pod）
ssh <user>@34.48.255.154
# 克隆代码、配置 .env.production、创建 docker-compose.override.yaml

# 4. 验证基础设施
gcloud compute instances list
dig api.ruralneighbor.com +short
```

---

**当前状态**：基础设施已 95% 就绪，仅待 Cloudflare DNS 应用 + Secret 值填充。Pod 部署暂缓，待基础设施验证完成后单独执行。


