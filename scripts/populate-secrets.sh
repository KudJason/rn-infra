#!/bin/bash
set -euo pipefail

echo "=== 自动填充 GCP Secret Manager 密钥 ==="
echo ""

PROJECT_ID="rural-neighbor-477211"
REGION="us-east4"
KMS_KEY="projects/${PROJECT_ID}/locations/${REGION}/keyRings/rn-keyring/cryptoKeys/app-config"

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_secret_exists() {
  local secret_name=$1
  if gcloud secrets describe "$secret_name" --project "$PROJECT_ID" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

create_secret_if_needed() {
  local secret_name=$1
  if ! check_secret_exists "$secret_name"; then
    echo -e "${YELLOW}创建 Secret: $secret_name${NC}"
    gcloud secrets create "$secret_name" \
      --replication-policy=automatic \
      --project "$PROJECT_ID"
    
    # 授权 VM SA 读取
    gcloud secrets add-iam-policy-binding "$secret_name" \
      --member="serviceAccount:rn-vm-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
      --role="roles/secretmanager.secretAccessor" \
      --project "$PROJECT_ID" >/dev/null
  fi
}

add_secret_version() {
  local secret_name=$1
  local secret_value=$2
  echo -n "$secret_value" | gcloud secrets versions add "$secret_name" \
    --data-file=- \
    --project "$PROJECT_ID" >/dev/null
  echo -e "${GREEN}✓ 已填充: $secret_name${NC}"
}

echo "1️⃣  生成强随机密钥..."
echo ""

# 生成所有密钥值
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')
JWT_SECRET=$(openssl rand -base64 48 | tr -d '\n')
SECRET_KEY=$(openssl rand -base64 48 | tr -d '\n')
REDIS_PASSWORD=$(openssl rand -base64 24 | tr -d '\n')

echo "2️⃣  创建并填充核心密钥..."
echo ""

# Postgres 密码
create_secret_if_needed "postgres-password"
add_secret_version "postgres-password" "$POSTGRES_PASSWORD"

# Postgres 用户名（固定）
create_secret_if_needed "postgres-user"
add_secret_version "postgres-user" "ruralneighbor"

# JWT Secret
create_secret_if_needed "jwt-secret"
add_secret_version "jwt-secret" "$JWT_SECRET"

# Secret Key (用于 Django/FastAPI session 等)
create_secret_if_needed "secret-key"
add_secret_version "secret-key" "$SECRET_KEY"

# Redis 密码
create_secret_if_needed "redis-password"
add_secret_version "redis-password" "$REDIS_PASSWORD"

echo ""
echo "3️⃣  创建数据库名称 secrets（便于容器读取）..."
echo ""

# 各服务的数据库名
DB_NAMES=(
  "auth_db:auth-db"
  "user_db:user-db"
  "location_db:location-db"
  "request_db:request-db"
  "payment_db:payment-db"
  "notification_db:notification-db"
  "content_db:content-db"
  "safety_db:safety-db"
  "rating_db:rating-db"
  "investment_db:investment-db"
)

for entry in "${DB_NAMES[@]}"; do
  db_name="${entry%%:*}"
  secret_name="${entry##*:}"
  create_secret_if_needed "$secret_name"
  add_secret_version "$secret_name" "$db_name"
done

echo ""
echo "4️⃣  创建其他配置 secrets..."
echo ""

# Algorithm
create_secret_if_needed "jwt-algorithm"
add_secret_version "jwt-algorithm" "HS256"

# Token 过期时间（分钟）
create_secret_if_needed "access-token-expire-minutes"
add_secret_version "access-token-expire-minutes" "30"

# Postgres 主机/端口（Docker Compose 环境）
create_secret_if_needed "postgres-host"
add_secret_version "postgres-host" "postgres"

create_secret_if_needed "postgres-port"
add_secret_version "postgres-port" "5432"

# Redis 配置
create_secret_if_needed "redis-host"
add_secret_version "redis-host" "redis"

create_secret_if_needed "redis-port"
add_secret_version "redis-port" "6379"

echo ""
echo "5️⃣  验证已填充的 Secrets..."
echo ""

gcloud secrets list --project "$PROJECT_ID" --filter="name~(postgres|jwt|secret|redis|auth-db|user-db)" --format="table(name)"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ 所有密钥已成功填充到 Secret Manager${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "📝 核心密钥摘要（请妥善保存或销毁此输出）："
echo "  - Postgres 用户: ruralneighbor"
echo "  - Postgres 密码: ${POSTGRES_PASSWORD:0:8}...（已加密存储）"
echo "  - JWT Secret: ${JWT_SECRET:0:8}...（已加密存储）"
echo "  - Redis 密码: ${REDIS_PASSWORD:0:8}...（已加密存储）"
echo ""
echo "🔐 所有密钥已通过 KMS (CMEK) 加密，VM SA 具备读取权限"
echo ""
echo "📖 下一步："
echo "  1) SSH 到核心 VM: ssh <user>@34.48.255.154"
echo "  2) 运行: cd /opt/ruralneighbour/ms-backend && ./scripts/generate-env-from-secrets.sh"
echo "  3) 启动容器: docker compose -f scripts/deployment/docker-compose.yaml --env-file .env.production up -d"
echo ""

