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
