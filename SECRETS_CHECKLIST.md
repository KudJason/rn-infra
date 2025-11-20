# Secrets 填充清单

本清单列出所有需要手动填充的敏感配置。**请勿将实际密钥值提交到 git。**

---

## GCP Secret Manager 密钥（需填充）

项目：`rural-neighbor-477211`  
区域：`us-east4`  
加密：CMEK（KMS `rn-keyring/app-config`）

### 1. 数据库密码 (`db-password`)
- **用途**：PostgreSQL 数据库连接密码
- **建议**：16+ 字符强密码（大小写+数字+符号）
- **填充命令**：
```bash
echo -n "YOUR_STRONG_DB_PASSWORD" | gcloud secrets versions add db-password \
  --data-file=- \
  --project rural-neighbor-477211
```
- **示例生成强密码**（可选）：
```bash
openssl rand -base64 24
```

---

### 2. JWT 密钥 (`jwt-secret`)
- **用途**：JWT Token 签名与验证
- **建议**：32+ 字符随机字符串（Base64 编码）
- **填充命令**：
```bash
echo -n "YOUR_JWT_SECRET_KEY" | gcloud secrets versions add jwt-secret \
  --data-file=- \
  --project rural-neighbor-477211
```
- **示例生成随机密钥**（推荐）：
```bash
openssl rand -base64 32 | tr -d '\n'
```

---

## 其他可能需要的密钥（根据应用需求补充）

### 3. Redis 密码（可选，当前未启用）
- **名称**：`redis-password`
- **用途**：Redis 连接鉴权（若需要）
- **创建+填充**：
```bash
# 创建 Secret
gcloud secrets create redis-password \
  --replication-policy=user-managed \
  --locations=us-east4 \
  --kms-key-name=projects/rural-neighbor-477211/locations/us-east4/keyRings/rn-keyring/cryptoKeys/app-config \
  --project rural-neighbor-477211

# 填充值
echo -n "YOUR_REDIS_PASSWORD" | gcloud secrets versions add redis-password \
  --data-file=- \
  --project rural-neighbor-477211

# 授权 VM SA 读取
gcloud secrets add-iam-policy-binding redis-password \
  --member="serviceAccount:rn-vm-sa@rural-neighbor-477211.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project rural-neighbor-477211
```

---

### 4. Stripe API Key（如需支付集成）
- **名称**：`stripe-api-key`
- **用途**：Payment Service 的 Stripe 私钥
- **创建+填充**：
```bash
gcloud secrets create stripe-api-key \
  --replication-policy=user-managed \
  --locations=us-east4 \
  --kms-key-name=projects/rural-neighbor-477211/locations/us-east4/keyRings/rn-keyring/cryptoKeys/app-config \
  --project rural-neighbor-477211

echo -n "sk_live_YOUR_STRIPE_KEY" | gcloud secrets versions add stripe-api-key \
  --data-file=- \
  --project rural-neighbor-477211

gcloud secrets add-iam-policy-binding stripe-api-key \
  --member="serviceAccount:rn-vm-sa@rural-neighbor-477211.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project rural-neighbor-477211
```

---

### 5. SendGrid API Key（如需邮件服务）
- **名称**：`sendgrid-api-key`
- **用途**：Notification Service 的邮件发送
- **创建+填充**：
```bash
gcloud secrets create sendgrid-api-key \
  --replication-policy=user-managed \
  --locations=us-east4 \
  --kms-key-name=projects/rural-neighbor-477211/locations/us-east4/keyRings/rn-keyring/cryptoKeys/app-config \
  --project rural-neighbor-477211

echo -n "SG.YOUR_SENDGRID_KEY" | gcloud secrets versions add sendgrid-api-key \
  --data-file=- \
  --project rural-neighbor-477211

gcloud secrets add-iam-policy-binding sendgrid-api-key \
  --member="serviceAccount:rn-vm-sa@rural-neighbor-477211.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project rural-neighbor-477211
```

---

### 6. AWS S3 Credentials（如需对象存储）
- **名称**：`aws-access-key-id` / `aws-secret-access-key`
- **用途**：Content Service 的文件上传（若用 S3）
- **创建+填充**：
```bash
# Access Key ID
gcloud secrets create aws-access-key-id \
  --replication-policy=user-managed \
  --locations=us-east4 \
  --kms-key-name=projects/rural-neighbor-477211/locations/us-east4/keyRings/rn-keyring/cryptoKeys/app-config \
  --project rural-neighbor-477211

echo -n "AKIA..." | gcloud secrets versions add aws-access-key-id \
  --data-file=- \
  --project rural-neighbor-477211

# Secret Access Key
gcloud secrets create aws-secret-access-key \
  --replication-policy=user-managed \
  --locations=us-east4 \
  --kms-key-name=projects/rural-neighbor-477211/locations/us-east4/keyRings/rn-keyring/cryptoKeys/app-config \
  --project rural-neighbor-477211

echo -n "YOUR_SECRET_KEY" | gcloud secrets versions add aws-secret-access-key \
  --data-file=- \
  --project rural-neighbor-477211

# 授权
gcloud secrets add-iam-policy-binding aws-access-key-id \
  --member="serviceAccount:rn-vm-sa@rural-neighbor-477211.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project rural-neighbor-477211

gcloud secrets add-iam-policy-binding aws-secret-access-key \
  --member="serviceAccount:rn-vm-sa@rural-neighbor-477211.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project rural-neighbor-477211
```

---

## 验证已填充的 Secret

```bash
# 列出所有 Secret
gcloud secrets list --project rural-neighbor-477211

# 检查某个 Secret 是否有版本
gcloud secrets versions list db-password --project rural-neighbor-477211

# 测试读取（在核心 VM 上）
gcloud secrets versions access latest --secret=db-password --project rural-neighbor-477211
```

---

## 在核心 VM 上使用 Secrets

SSH 到核心 VM 后，生成应用环境文件：

```bash
ssh <你的账号>@34.48.255.154

cd /opt/ruralneighbour/ms-backend

# 自动从 Secret Manager 拉取并生成 .env.production
cat > .env.production <<ENV
# Database
POSTGRES_USER=ruralneighbor
POSTGRES_PASSWORD=$(gcloud secrets versions access latest --secret=db-password)
POSTGRES_DB=ruralneighbor_prod
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
DATABASE_URL=postgresql://ruralneighbor:$(gcloud secrets versions access latest --secret=db-password)@postgres:5432/ruralneighbor_prod

# JWT
JWT_SECRET=$(gcloud secrets versions access latest --secret=jwt-secret)
SECRET_KEY=$(gcloud secrets versions access latest --secret=jwt-secret)
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_URL=redis://redis:6379/0

# Optional: Stripe (如启用)
# STRIPE_API_KEY=$(gcloud secrets versions access latest --secret=stripe-api-key)

# Optional: SendGrid (如启用)
# SENDGRID_API_KEY=$(gcloud secrets versions access latest --secret=sendgrid-api-key)

# Optional: AWS S3 (如启用)
# AWS_ACCESS_KEY_ID=$(gcloud secrets versions access latest --secret=aws-access-key-id)
# AWS_SECRET_ACCESS_KEY=$(gcloud secrets versions access latest --secret=aws-secret-access-key)
# AWS_REGION=us-east-1
# AWS_BUCKET_NAME=your-bucket
ENV

# 验证文件生成
cat .env.production | head -20
```

然后在 docker-compose 启动时引用：
```bash
docker compose -f scripts/deployment/docker-compose.yaml \
  -f docker-compose.override.yaml \
  --env-file .env.production \
  up -d
```

---

## 最小必填（启动前）

✅ **必须**：
1. `db-password`
2. `jwt-secret`

⚠️ **可选**（按业务功能需要）：
3. `redis-password`（若启用 Redis AUTH）
4. `stripe-api-key`（支付集成）
5. `sendgrid-api-key`（邮件通知）
6. `aws-access-key-id` + `aws-secret-access-key`（S3 存储）

---

## 安全提示

- 填充时使用 `echo -n` 避免换行符进入密钥值
- 生产环境使用强随机密码（推荐用 `openssl rand -base64 <length>`）
- 填充完成后，删除本机 shell 历史中的明文密钥（`history -c` 或退出终端）
- 定期轮换密钥（特别是 JWT secret）
- 在 CI/CD 中可通过 Workload Identity 读取，无需导出密钥文件

---

**当前状态**：已创建 `db-password` 与 `jwt-secret` 两个 Secret（CMEK 加密），等待你填充值。

