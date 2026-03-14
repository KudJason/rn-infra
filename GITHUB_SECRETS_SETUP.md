# GitHub Secrets Configuration for ruralneighbour-k8s

**Date:** November 4, 2025  
**Repository:** KudJason/ruralneighbour-k8s  
**GCP Project:** rural-neighbor-1

---

## ✅ GCP Workload Identity Setup Complete

All GCP resources have been successfully created:
- ✅ Workload Identity Pool: `github-actions-pool`
- ✅ OIDC Provider: `github-provider`
- ✅ Service Account: `github-actions-sa`
- ✅ Artifact Registry Repository: `rn-backend` (us-central1)
- ✅ IAM Permissions: `roles/artifactregistry.writer`

---

## 📋 GitHub Secrets to Add

Go to: https://github.com/KudJason/ruralneighbour-k8s/settings/secrets/actions

Click: **New repository secret** for each of the following:

### Secret 1: `GCP_WORKLOAD_IDENTITY_PROVIDER`

**Value:**
```
projects/763414052591/locations/global/workloadIdentityPools/github-actions-pool/providers/github-provider
```

**Purpose:** Allows GitHub Actions to authenticate with GCP using Workload Identity Federation

**Note:** The Service Account needs the following roles:
- `roles/artifactregistry.writer` - Push Docker images
- `roles/compute.instanceAdmin.v1` - SSH access to VMs (for deployment)

---

### Secret 2: `GCP_SERVICE_ACCOUNT`

**Value:**
```
github-actions-sa@rural-neighbor-1.iam.gserviceaccount.com
```

**Purpose:** The service account email that GitHub Actions will impersonate

---

### Secret 3: `VM_SSH_USER`

**Value:** (You need to provide your VM SSH username)
```
<your-username>
```

**Examples:**
- If your VM user is `masterjia`, enter: `masterjia`
- If your VM user is `yourname`, enter: `yourname`

**Purpose:** SSH username for connecting to your core VM at 34.48.255.154

---

### Secret 4: `VM_SSH_PRIVATE_KEY`

**Status:** ⚠️ Needs to be generated or retrieved

#### Option A: Generate New SSH Key (Recommended)

Run these commands on your local machine:

```bash
# 1. Generate dedicated SSH key for GitHub Actions
ssh-keygen -t ed25519 -f ~/.ssh/github_actions_rsa -N ""

# 2. Copy public key to your core VM (replace <your-user> with actual username)
ssh-copy-id -i ~/.ssh/github_actions_rsa.pub <your-user>@34.48.255.154

# 3. Display private key content (copy this entire output)
cat ~/.ssh/github_actions_rsa
```

#### Option B: Use Existing SSH Key

If you already have SSH access to the VM:

```bash
# Display your existing private key
cat ~/.ssh/id_rsa
# or
cat ~/.ssh/id_ed25519
```

**⚠️ Important:** 
- Copy the **ENTIRE** private key including the BEGIN and END lines
- Example format:
```
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
...
(many lines of key data)
...
-----END OPENSSH PRIVATE KEY-----
```

**Purpose:** Private key for SSH authentication to deploy to the VM

---

## 🚀 Quick Setup Checklist

- [ ] Add `GCP_WORKLOAD_IDENTITY_PROVIDER` to GitHub Secrets
- [ ] Add `GCP_SERVICE_ACCOUNT` to GitHub Secrets  
- [ ] Determine your VM SSH username
- [ ] Add `VM_SSH_USER` to GitHub Secrets
- [ ] Generate/retrieve SSH private key
- [ ] Add `VM_SSH_PRIVATE_KEY` to GitHub Secrets
- [ ] Test GitHub Actions workflow

---

## 🔧 How to Add Secrets

### Step-by-Step:

1. **Go to GitHub Repository:**
   - URL: https://github.com/KudJason/ruralneighbour-k8s

2. **Navigate to Settings:**
   - Click on **Settings** tab
   - Click on **Secrets and variables** → **Actions**

3. **Add Each Secret:**
   - Click **New repository secret**
   - Enter the secret name exactly as shown (case-sensitive)
   - Paste the value
   - Click **Add secret**
   - Repeat for all 4 secrets

---

## 🧪 Testing the Setup

After adding all secrets, test the configuration:

### Option 1: Manual Workflow Trigger

1. Go to: https://github.com/KudJason/ruralneighbour-k8s/actions
2. Select your deployment workflow
3. Click **Run workflow**
4. Monitor the execution

### Option 2: Push to Trigger

```bash
cd /Users/jasonjia/Documents/codebase/ruralneighbour/ms-backend
git add .
git commit -m "test: trigger GitHub Actions deployment"
git push origin develop
```

---

## 📊 What This Enables

Once all secrets are configured, your GitHub Actions workflow can:

1. ✅ Authenticate to GCP without storing JSON keys
2. ✅ Push Docker images to Artifact Registry (`us-central1-docker.pkg.dev/rural-neighbor-1/rn-backend`)
3. ✅ SSH into your core VM (34.48.255.154)
4. ✅ Deploy services to MicroK8s cluster
5. ✅ Run post-deployment tests

---

## 🔒 Security Best Practices

### ✅ Good (What We Did)
- Using Workload Identity Federation (no JSON keys stored)
- OIDC authentication tied to specific repository
- Dedicated service account with minimal permissions
- Dedicated SSH key for GitHub Actions

### ⚠️ Important Reminders
- Never commit private keys to git
- Never expose secrets in logs
- Rotate SSH keys periodically
- Review GitHub Actions logs carefully

---

## 🆘 Troubleshooting

### Problem: "Could not get existing SSH user"

**Solution:** Make sure you know your VM SSH username. You can check by:
```bash
# If you can currently SSH to the VM
ssh <username>@34.48.255.154
whoami
```

### Problem: "Permission denied (publickey)"

**Solution:** 
- Ensure public key is added to VM's `~/.ssh/authorized_keys`
- Run: `ssh-copy-id -i ~/.ssh/github_actions_rsa.pub <user>@34.48.255.154`

### Problem: "Workload Identity authentication failed"

**Solution:**
- Double-check the secret values (no extra spaces/newlines)
- Verify repository name is exactly: `KudJason/ruralneighbour-k8s`

### Problem: "artifactregistry.writer permission denied"

**Solution:** 
- This shouldn't happen as we just granted it
- If it does, wait 1-2 minutes for IAM propagation

---

## 📚 Additional Resources

### GCP Resources Created
- **Workload Identity Pool:** `github-actions-pool`
- **Provider:** `github-provider`  
- **Service Account:** `github-actions-sa@rural-neighbor-1.iam.gserviceaccount.com`
- **Artifact Registry:** `us-central1-docker.pkg.dev/rural-neighbor-1/rn-backend`

### GitHub Actions Workflow
- File: `ms-backend/.github/workflows/deploy-backend.yml`
- Trigger: Push to `develop` or `main` branch
- Manual: Actions tab → Run workflow

### Related Documentation
- [GCP Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [Google Artifact Registry](https://cloud.google.com/artifact-registry/docs)

---

## ✅ Summary

**What's Done:**
- ✅ GCP Workload Identity fully configured
- ✅ Service account with Artifact Registry permissions
- ✅ OIDC provider linked to your GitHub repository
- ✅ Artifact Registry repository created

**What You Need to Do:**
1. Add 4 secrets to GitHub (2 are ready, 2 need your input)
2. Generate/retrieve SSH key for VM access
3. Test the GitHub Actions workflow

**Next Steps After Adding Secrets:**
1. Trigger a GitHub Actions workflow
2. Monitor the deployment process
3. Verify services are running on your VM

---

**Generated:** November 4, 2025  
**Script Used:** `infra/scripts/setup-github-workload-identity.sh`


