#!/bin/bash
set -euo pipefail

echo "=== 配置 GitHub Actions Workload Identity ==="
echo ""

PROJECT_ID="rural-neighbor-477211"
POOL_NAME="github-actions-pool"
PROVIDER_NAME="github-provider"
SA_NAME="github-actions-sa"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 获取 GitHub 仓库信息
if [ $# -eq 0 ]; then
  echo -e "${YELLOW}用法: $0 <GitHub仓库全名>${NC}"
  echo "示例: $0 username/ruralneighbour"
  exit 1
fi

GITHUB_REPO="$1"

echo ""
echo "配置参数："
echo "  - GCP 项目: $PROJECT_ID"
echo "  - GitHub 仓库: $GITHUB_REPO"
echo "  - Workload Identity Pool: $POOL_NAME"
echo "  - Provider: $PROVIDER_NAME"
echo "  - Service Account: $SA_NAME"
echo ""

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

echo ""
echo "1️⃣  启用所需 API..."
gcloud services enable \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com \
  sts.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet

echo ""
echo "2️⃣  创建 Workload Identity Pool..."
if gcloud iam workload-identity-pools describe "$POOL_NAME" \
  --location="global" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "   Pool 已存在，跳过"
else
  gcloud iam workload-identity-pools create "$POOL_NAME" \
    --location="global" \
    --display-name="GitHub Actions Pool" \
    --project="$PROJECT_ID"
  echo -e "${GREEN}✓ 已创建 Pool${NC}"
fi

echo ""
echo "3️⃣  创建 OIDC Provider（关联 GitHub）..."
if gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" \
  --location="global" \
  --workload-identity-pool="$POOL_NAME" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "   Provider 已存在，跳过"
else
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_NAME" \
    --location="global" \
    --workload-identity-pool="$POOL_NAME" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.actor=assertion.actor" \
    --attribute-condition="assertion.repository=='${GITHUB_REPO}'" \
    --project="$PROJECT_ID"
  echo -e "${GREEN}✓ 已创建 Provider${NC}"
fi

echo ""
echo "4️⃣  创建 Service Account..."
if gcloud iam service-accounts describe "${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "   Service Account 已存在，跳过"
else
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="GitHub Actions Deployer" \
    --project="$PROJECT_ID"
  echo -e "${GREEN}✓ 已创建 Service Account${NC}"
fi

SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo ""
echo "5️⃣  授予权限..."

# Artifact Registry 写入（推送镜像）
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/artifactregistry.writer" \
  --condition=None \
  --quiet

# VM SSH 访问权限（部署到中心服务器）
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/compute.instanceAdmin.v1" \
  --condition=None \
  --quiet

# 如果需要拉取 Secret Manager（可选，核心 VM SA 已有权限）
# gcloud projects add-iam-policy-binding "$PROJECT_ID" \
#   --member="serviceAccount:${SA_EMAIL}" \
#   --role="roles/secretmanager.secretAccessor" \
#   --condition=None \
#   --quiet

echo -e "${GREEN}✓ 已授予 artifactregistry.writer${NC}"

echo ""
echo "6️⃣  绑定 Workload Identity..."
gcloud iam service-accounts add-iam-policy-binding \
  "$SA_EMAIL" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/attribute.repository/${GITHUB_REPO}" \
  --project="$PROJECT_ID" \
  --quiet

echo -e "${GREEN}✓ 已绑定 Workload Identity${NC}"

echo ""
echo "7️⃣  创建 Artifact Registry 仓库（若不存在）..."
if gcloud artifacts repositories describe rn-backend \
  --location=us-east4 \
  --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "   仓库 rn-backend 已存在，跳过"
else
  gcloud artifacts repositories create rn-backend \
    --repository-format=docker \
    --location=us-east4 \
    --description="RuralNeighbour Backend Services" \
    --project="$PROJECT_ID"
  echo -e "${GREEN}✓ 已创建 Artifact Registry 仓库${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Workload Identity 配置完成${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}📝 请将以下值添加到 GitHub Secrets:${NC}"
echo ""
echo -e "${YELLOW}Secrets 设置路径：${NC}"
echo "  GitHub 仓库 → Settings → Secrets and variables → Actions → New repository secret"
echo ""
echo "---"
echo -e "${YELLOW}Secret 1: GCP_WORKLOAD_IDENTITY_PROVIDER${NC}"
echo "projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/providers/${PROVIDER_NAME}"
echo ""
echo "---"
echo -e "${YELLOW}Secret 2: GCP_SERVICE_ACCOUNT${NC}"
echo "$SA_EMAIL"
echo ""
echo "---"
echo -e "${YELLOW}Secret 3: VM_SSH_USER${NC}"
echo "<你的核心 VM SSH 用户名，例如：youruser>"
echo ""
echo "---"
echo -e "${YELLOW}Secret 4: VM_SSH_PRIVATE_KEY${NC}"
echo "<你的 SSH 私钥完整内容，见下方生成命令>"
echo ""
echo "========================================="
echo ""
echo "🔑 SSH Key 生成与配置（若还没有）:"
echo ""
echo "# 1. 生成专用 SSH Key（本地执行）"
echo "ssh-keygen -t ed25519 -f ~/.ssh/github_actions_rsa -N \"\""
echo ""
echo "# 2. 复制公钥到核心 VM"
echo "ssh-copy-id -i ~/.ssh/github_actions_rsa.pub <你的用户>@34.48.255.154"
echo ""
echo "# 3. 查看私钥内容（复制到 GitHub Secret VM_SSH_PRIVATE_KEY）"
echo "cat ~/.ssh/github_actions_rsa"
echo ""
echo "========================================="
echo ""
echo -e "${GREEN}✓ 所有配置完成，按上述步骤添加 GitHub Secrets 后即可使用 GitHub Actions 部署${NC}"
echo ""

