# Secrets 填充清单

本清单列出所有需要手动填充的敏感配置。**请勿将实际密钥值提交到 git。**

---

## GCP Secret Manager 密钥（需填充）

项目：`rural-neighbor-1`  
区域：`us-central1`  
加密：CMEK（KMS `rn-keyring/app-config`）

### 1. 数据库密码 (`db-password`)
- **用途**：PostgreSQL 数据库连接密码
- **建议**：16+ 字符强密码（大小写+数字+符号）
- **填充命令**：
```bash
echo -n "YOUR_STRONG_DB_PASSWORD" | gcloud secrets versions add db-password \
  --data-file=- \
  --project rural-neighbor-1
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
  --project rural-neighbor-1
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
  --locations=us-central1 \
  --kms-key-name=projects/rural-neighbor-1/locations/us-central1/keyRings/rn-keyring/cryptoKeys/app-config \
  --project rural-neighbor-1

# 填充值
echo -n "YOUR_REDIS_PASSWORD" | gcloud secrets versions add redis-password \
  --data-file=- \
  --project rural-neighbor-1

# 授权 VM SA 读取
gcloud secrets add-iam-policy-binding redis-password \
  --member="serviceAccount:rn-vm-sa@rural-neighbor-1.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project rural-neighbor-1
```

---

### 4. Stripe API Key（如需支付集成）
- **名称**：`stripe-api-key`
- **用途**：Payment Service 的 Stripe 私钥
- **创建+填充**：
```bash
gcloud secrets create stripe-api-key \
  --replication-policy=user-managed \
  --locations=us-central1 \
  --kms-key-name=projects/rural-neighbor-1/locations/us-central1/keyRings/rn-keyring/cryptoKeys/app-config \
  --project rural-neighbor-1

echo -n "sk_live_YOUR_STRIPE_KEY" | gcloud secrets versions add stripe-api-key \
  --data-file=- \
  --project rural-neighbor-1

gcloud secrets add-iam-policy-binding stripe-api-key \
  --member="serviceAccount:rn-vm-sa@rural-neighbor-1.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project rural-neighbor-1
```

---

### 5. AWS Credentials（用于 SNS SMS 和 SES SMTP Email）
- **名称**：`aws-access-key-id`, `aws-secret-access-key`, `aws-region`, `aws-ses-smtp-password`
- **用途**：Auth Service 的 SMS（SNS）和 Email（SES SMTP）服务
- **创建+填充**：
```bash
# AWS Access Key ID (用于 SNS API 和 SES SMTP 用户名)
gcloud secrets create aws-access-key-id \
  --replication-policy=user-managed \
  --locations=us-central1 \
  --kms-key-name=projects/rural-neighbor-1/locations/us-central1/keyRings/rn-keyring/cryptoKeys/app-config \
  --project rural-neighbor-1

echo -n "AKIA..." | gcloud secrets versions add aws-access-key-id \
  --data-file=- \
  --project rural-neighbor-1

# AWS Secret Access Key (用于 SNS API)
gcloud secrets create aws-secret-access-key \
  --replication-policy=user-managed \
  --locations=us-central1 \
  --kms-key-name=projects/rural-neighbor-1/locations/us-central1/keyRings/rn-keyring/cryptoKeys/app-config \
  --project rural-neighbor-1

echo -n "YOUR_SECRET_KEY" | gcloud secrets versions add aws-secret-access-key \
  --data-file=- \
  --project rural-neighbor-1

# AWS Region
gcloud secrets create aws-region \
  --replication-policy=user-managed \
  --locations=us-central1 \
  --kms-key-name=projects/rural-neighbor-1/locations/us-central1/keyRings/rn-keyring/cryptoKeys/app-config \
  --project rural-neighbor-1

echo -n "us-east-1" | gcloud secrets versions add aws-region \
  --data-file=- \
  --project rural-neighbor-1

# AWS SES SMTP Password (必须从 IAM 生成，不是普通的 secret key)
# 获取方法：
# 1. 登录 AWS Console -> IAM -> Users -> 选择用户 -> Security credentials
# 2. 在 "SMTP credentials" 部分点击 "Create SMTP credentials"
# 3. 下载或复制生成的 SMTP 密码（只能显示一次）
gcloud secrets create aws-ses-smtp-password \
  --replication-policy=user-managed \
  --locations=us-central1 \
  --kms-key-name=projects/rural-neighbor-1/locations/us-central1/keyRings/rn-keyring/cryptoKeys/app-config \
  --project rural-neighbor-1

echo -n "YOUR_SMTP_PASSWORD_FROM_IAM" | gcloud secrets versions add aws-ses-smtp-password \
  --data-file=- \
  --project rural-neighbor-1

# 设置 IAM 权限
for secret in aws-access-key-id aws-secret-access-key aws-region aws-ses-smtp-password; do
  gcloud secrets add-iam-policy-binding "$secret" \
    --member="serviceAccount:rn-vm-sa@rural-neighbor-1.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" \
    --project rural-neighbor-1
done
```

**重要提示：AWS SES SMTP 密码获取方法**
1. 登录 AWS Console，进入 IAM 服务
2. 选择用于 SES 的 IAM 用户
3. 进入 "Security credentials" 标签页
4. 在 "SMTP credentials" 部分点击 "Create SMTP credentials"
5. 下载或复制生成的 SMTP 密码（**只能显示一次，请妥善保存**）
6. 确保该 IAM 用户具有 `ses:SendRawEmail` 权限（或使用 `AmazonSESFullAccess` 策略）

### 6. Email Configuration（邮件配置）
- **名称**：`from-email`, `frontend-url`
- **用途**：Auth Service 的邮件发送配置（发件人地址和前端 URL）
- **创建+填充**：
```bash
# From Email
gcloud secrets create from-email \
  --replication-policy=user-managed \
  --locations=us-central1 \
  --kms-key-name=projects/rural-neighbor-1/locations/us-central1/keyRings/rn-keyring/cryptoKeys/app-config \
  --project rural-neighbor-1

echo -n "noreply@ruralneighbor.com" | gcloud secrets versions add from-email \
  --data-file=- \
  --project rural-neighbor-1

# Frontend URL
gcloud secrets create frontend-url \
  --replication-policy=user-managed \
  --locations=us-central1 \
  --kms-key-name=projects/rural-neighbor-1/locations/us-central1/keyRings/rn-keyring/cryptoKeys/app-config \
  --project rural-neighbor-1

echo -n "https://ruralneighbor.com" | gcloud secrets versions add frontend-url \
  --data-file=- \
  --project rural-neighbor-1

# 设置 IAM 权限
for secret in from-email frontend-url; do
  gcloud secrets add-iam-policy-binding "$secret" \
    --member="serviceAccount:rn-vm-sa@rural-neighbor-1.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" \
    --project rural-neighbor-1
done
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
  --locations=us-central1 \
  --kms-key-name=projects/rural-neighbor-1/locations/us-central1/keyRings/rn-keyring/cryptoKeys/app-config \
  --project rural-neighbor-1

echo -n "AKIA..." | gcloud secrets versions add aws-access-key-id \
  --data-file=- \
  --project rural-neighbor-1

# Secret Access Key
gcloud secrets create aws-secret-access-key \
  --replication-policy=user-managed \
  --locations=us-central1 \
  --kms-key-name=projects/rural-neighbor-1/locations/us-central1/keyRings/rn-keyring/cryptoKeys/app-config \
  --project rural-neighbor-1

echo -n "YOUR_SECRET_KEY" | gcloud secrets versions add aws-secret-access-key \
  --data-file=- \
  --project rural-neighbor-1

# 授权
gcloud secrets add-iam-policy-binding aws-access-key-id \
  --member="serviceAccount:rn-vm-sa@rural-neighbor-1.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project rural-neighbor-1

gcloud secrets add-iam-policy-binding aws-secret-access-key \
  --member="serviceAccount:rn-vm-sa@rural-neighbor-1.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project rural-neighbor-1
```

---

## 验证已填充的 Secret

```bash
# 列出所有 Secret
gcloud secrets list --project rural-neighbor-1

# 检查某个 Secret 是否有版本
gcloud secrets versions list db-password --project rural-neighbor-1

# 测试读取（在核心 VM 上）
gcloud secrets versions access latest --secret=db-password --project rural-neighbor-1
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

# AWS Credentials (for SNS SMS and SES Email)
AWS_ACCESS_KEY_ID=$(gcloud secrets versions access latest --secret=aws-access-key-id)
AWS_SECRET_ACCESS_KEY=$(gcloud secrets versions access latest --secret=aws-secret-access-key)
AWS_REGION=$(gcloud secrets versions access latest --secret=aws-region)
FROM_EMAIL=$(gcloud secrets versions access latest --secret=from-email)
FRONTEND_URL=$(gcloud secrets versions access latest --secret=frontend-url)

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
5. `aws-access-key-id`, `aws-secret-access-key`, `aws-region`, `aws-ses-smtp-password`（AWS SNS/SES SMTP）
6. `from-email`, `frontend-url`（邮件配置）
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

