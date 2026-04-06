# No-IAM-Admin Runbook (gcp-vm-hybrid)

Date: 2026-03-14

## What has been implemented

### 1) Worker startup reliability hardening (`mig.tf`)
- Added startup logging to `/var/log/rn-worker-startup.log`.
- Removed hardcoded project id usage in secret fetch path and switched to Terraform variable (`var.project_id`).
- Increased K3S token fetch retries (`90 x 10s = 15min`) to tolerate delayed core bootstrap and IAM propagation.
- Added guardrails:
  - fail fast when token is still empty
  - fail fast when core `MASTER_IP` is empty
- Added API reachability loop for `MASTER_IP:6443` before installing agent.
- Forced explicit agent install mode:
  - `sh -s - agent --node-name "$(hostname)"`
- Added dependency so MIG is created after core resource:
  - `depends_on = [google_compute_instance.core]`

### 2) Core token publish hardening (`on_demand_vm.tf`)
- Replaced process substitution (`--data-file=<(...)`) with temp file upload (more shell-safe in startup scripts).
- Added retry loop (`30 x 10s = 5min`) for `gcloud secrets versions add`.
- Added clear progress logs during secret publish attempts.

## Why this helps without IAM Admin
- You no longer need repeated manual IAM updates for day-to-day deploys.
- As long as these one-time conditions are already true, normal apply/deploy should work:
  1. Secret `K3S_CLUSTER_TOKEN` exists
  2. VM SA has `roles/secretmanager.secretAccessor` on that secret
- New retries + readiness checks absorb common race conditions that used to break worker join.

## Validation completed
- `terraform validate` => success
- `terraform fmt` applied
- `terraform validate` after fmt => success

## Day-2 operation (no IAM admin)

```bash
cd infra/terraform/gcp-vm-hybrid
terraform plan
terraform apply
```

If workers still do not join, inspect:

```bash
gcloud compute ssh rn-core-vm --zone us-central1-a --project rural-neighbor-1 \
  --command "sudo k3s kubectl get nodes -o wide"

gcloud compute ssh rn-spot-<instance> --zone us-central1-a --project rural-neighbor-1 \
  --command "sudo tail -n 200 /var/log/rn-worker-startup.log; sudo systemctl status k3s-agent --no-pager"
```

## One-time admin prerequisites (if not already done)
- Create secret: `K3S_CLUSTER_TOKEN`
- Grant VM SA secret accessor on `K3S_CLUSTER_TOKEN`

These are one-time bootstrap actions by an admin and are outside normal no-admin operation.

## Cloudflare Tunnel — 将 Rancher 映射到 cowboy.ruralneighbor.com

适用场景：`rancher` 服务运行在集群内并通过 NodePort（或在本机 443）对外，可在 `rn-core-vm` 上用 `cloudflared` 将域名映射到本机的 Rancher origin。

步骤概览（顺序执行）：

1. 在工作站或有浏览器的机器上进行 `cloudflared login` 并创建 tunnel（只需一次交互授权）。
2. 将生成的 credentials JSON 拷贝到 `rn-core-vm` 的 `/root/.cloudflared/`。
3. 在 `rn-core-vm` 上写入 `/etc/cloudflared/config.yml`（示例在下），并以 systemd 启动 `cloudflared`。
4. 在 Cloudflare 控制台确认 `cowboy.ruralneighbor.com` 已指向 tunnel（或用 `cloudflared tunnel route dns` 创建记录）。

找出 Rancher 的 NodePort（在 `rn-core-vm` 上运行）：

```bash
sudo k3s kubectl get svc -n cattle-system rancher -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}' || echo 'N/A'
```

或从本地用 gcloud 运行：

```bash
gcloud compute ssh rn-core-vm --zone us-central1-a --project rural-neighbor-1 \
  --command "sudo k3s kubectl get svc -n cattle-system rancher -o jsonpath='{.spec.ports[?(@.name==\"https\")].nodePort}' || echo 'N/A'"
```

示例 `config.yml`（假设 NodePort 为 `30443`，Tunnel UUID 为 `<TUNNEL-UUID>`）：

```yaml
tunnel: <TUNNEL-UUID>
credentials-file: /root/.cloudflared/<TUNNEL-UUID>.json

ingress:
  - hostname: cowboy.ruralneighbor.com
    service: https://127.0.0.1:30443
    originRequest:
      noTLSVerify: true

  - service: http_status:404
```

创建 tunnel（在浏览器机器上）：

```bash
cloudflared login
cloudflared tunnel create rn-rancher
cloudflared tunnel route dns rn-rancher cowboy.ruralneighbor.com
```

把凭证文件拷贝到 `rn-core-vm`（示例使用 `gcloud compute scp`）：

```bash
gcloud compute scp ~/.cloudflared/<TUNNEL-UUID>.json rn-core-vm:/root/.cloudflared/ \
  --zone us-central1-a --project rural-neighbor-1
```

在 `rn-core-vm` 上创建 `/etc/cloudflared/config.yml`（使用上面的示例内容），然后安装 systemd 服务并启动：

```bash
sudo cloudflared service install
sudo systemctl enable --now cloudflared
sudo systemctl status cloudflared
```

验证（从外网访问）：

```bash
curl -kI https://cowboy.ruralneighbor.com
# 或浏览器直接打开 https://cowboy.ruralneighbor.com
```

安全提示：
- 如果 Rancher 使用自签证书，`noTLSVerify: true` 可临时绕过；长期请使用 Origin CA 或让 cert-manager 在集群内签发受信任证书并启用严格模式。
- 强烈建议配合 Cloudflare Access（Zero Trust）限制对 Rancher UI 的访问（SSO/MFA）。

如果需要，我可以：
- 生成填有当前 NodePort 的 `config.yml` 并把说明写回本文件（我已经把模板加入本 runbook）；或
- 在你提供 `<TUNNEL-UUID>.json` 后帮你将 credentials 上传到 `rn-core-vm` 并远程启用服务（需你授权执行 `gcloud compute scp`/ssh）。

