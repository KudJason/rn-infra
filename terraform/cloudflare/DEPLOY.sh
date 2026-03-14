#!/bin/bash
set -euo pipefail

#################################################################################
# Cloudflare Terraform 快速部署脚本
#################################################################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}${BOLD}   Cloudflare API Gateway 部署${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 检查 Cloudflare API Token
if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
    echo -e "${RED}❌ 错误: CLOUDFLARE_API_TOKEN 未设置${NC}"
    echo ""
    echo "请按以下步骤获取 API Token:"
    echo "1. 登录 https://dash.cloudflare.com"
    echo "2. My Profile → API Tokens → Create Token"
    echo "3. 使用 'Edit zone DNS' 模板"
    echo "4. 设置权限: Zone:DNS:Edit, Zone:Zone Settings:Edit"
    echo "5. 选择 Zone: ruralneighbor.com"
    echo "6. Create Token 并复制"
    echo ""
    echo "然后运行:"
    echo "  export CLOUDFLARE_API_TOKEN=\"your_token_here\""
    echo "  $0"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ Cloudflare API Token 已设置${NC}"
echo ""

# 切换到正确的目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 检查 Terraform
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}❌ 错误: Terraform 未安装${NC}"
    echo "请安装 Terraform: https://www.terraform.io/downloads"
    exit 1
fi

echo -e "${GREEN}✓ Terraform 已安装${NC}"
terraform version | head -1
echo ""

# 初始化
echo -e "${YELLOW}━━━ 初始化 Terraform ━━━${NC}"
echo ""
terraform init
echo ""

# 验证配置
echo -e "${YELLOW}━━━ 验证配置 ━━━${NC}"
echo ""
terraform validate
echo ""

# 计划
echo -e "${YELLOW}━━━ 生成部署计划 ━━━${NC}"
echo ""
terraform plan -out=tfplan
echo ""

# 询问确认
echo -e "${YELLOW}━━━ 准备应用变更 ━━━${NC}"
echo ""
echo -e "${CYAN}将要创建的资源:${NC}"
echo "  • DNS A 记录: api.ruralneighbor.com"
echo "  • SSL/TLS 设置"
echo "  • 速率限制规则"
echo "  • 页面规则 (2 条)"
echo ""

read -p "确认部署? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}部署已取消${NC}"
    rm -f tfplan
    exit 0
fi

# 应用
echo ""
echo -e "${YELLOW}━━━ 应用配置 ━━━${NC}"
echo ""
terraform apply tfplan
rm -f tfplan

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}   ✅ 部署完成！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 显示输出
echo -e "${CYAN}部署信息:${NC}"
terraform output
echo ""

# 验证指引
echo -e "${YELLOW}━━━ 后续步骤 ━━━${NC}"
echo ""
echo "1. 等待 DNS 传播 (1-5 分钟)"
echo ""
echo "2. 验证 DNS 解析:"
echo "   ${BLUE}dig api.ruralneighbor.com${NC}"
echo ""
echo "3. 测试 HTTPS 端点:"
echo "   ${BLUE}curl https://api.ruralneighbor.com/health${NC}"
echo "   ${BLUE}curl https://api.ruralneighbor.com/health/auth${NC}"
echo "   ${BLUE}curl https://api.ruralneighbor.com/health/user${NC}"
echo ""
echo "4. 查看 Cloudflare Dashboard:"
echo "   https://dash.cloudflare.com"
echo ""
echo -e "${GREEN}🎉 恭喜！API Gateway 已部署成功！${NC}"
echo ""




















