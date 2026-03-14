## 目标与概览
用 1 台按需 e2-medium 作为核心节点（入口 + 数据持久化），再用 1 个 MIG 维持 2 台 Spot e2-medium 跑无状态服务；避免使用外部负载均衡以控制固定费用；通过独立数据盘 + 每日快照 + GCS 逻辑备份降低数据风险。

预算目标：≈ 85 美元/月（3 个月 ≈ 255 美元），在 300 美元总预算内保留缓冲。使用 Cloudflare 免费版并将 MIG 规模设为 2 台 Spot，月度成本仍控制在 ≈ $80–$95 区间（按轻量出网与镜像存储）。

---

## 文件与资源定义

- `providers.tf`
  - 配置 Google 提供商与远端状态（GCS `tf-state-rural-neighbor-1/terraform/vm-hybrid`）。
  - 风险：无。

- `variables.tf`
  - 主要参数（项目、区域/可用区、机器类型、磁盘大小、MIG 规模、备份桶等）。
  - 风险：默认全开 0.0.0.0/0 访问（便于启动）。缓解：生产时改为公司出口 IP 段。

- `services.tf`
  - 启用 `compute/iam/logging/monitoring/storage` API。
  - 风险：启用 API 的权限不可过宽。缓解：最小化到本方案所需集合。

- `network.tf`
  - 防火墙：
    - 仅对核心 VM 开放 SSH(22) 与 Web(80/443)，打上标签 `rn-core-ssh`、`rn-core-web`。
    - Web(80/443) 仅接受 Cloudflare 官方 IPv4 段来源（`cloudflare_ipv4_ranges`），实现“只允许 Cloudflare 回源”。
    - 对 MIG 实例（标签 `rn-mig`）显式 `deny all ingress`，减少暴露面。
  - 风险：核心 VM 仍对公网开放 22/80/443。缓解：将 `allow_source_ranges` 收紧；后续可加 Fail2ban/WAF。

- `iam.tf`
  - 创建专用 SA `rn-vm-sa`；授予日志/监控写权限；创建 GCS 备份桶（版本化 + 30 天生命周期）并授予对象写权限。
  - 风险：`storage.objectAdmin` 范围较大。缓解：桶级别授予而非项目级；仅此备份桶。

- `on_demand_vm.tf`
  - 创建核心 VM：
    - Debian 12、e2-medium、引导盘 50GB。
    - 附加独立数据盘 50GB（`/data`），并写入 `/etc/fstab` 自动挂载。
    - 启用 Shielded VM、OS Login、阻止项目级 SSH Key 继承。
    - 安装 Docker 与 gcloud；放置 nightly 备份脚本（打包 `/data`，如 gcloud 可用则推送到 `gs://<backup-bucket>/nightly/`）。
    - 说明写入 `/etc/motd`，提示如何克隆代码与启动 compose。
  - 风险：
    - gcloud 安装可能失败导致首次未启用 GCS 备份。缓解：脚本容错 + 仍有磁盘每日快照作兜底。
    - 备份凭据依赖 VM SA。缓解：最小权限 + 桶级 IAM。

- `backup_snapshot.tf`
  - 资源策略：每日 03:00 创建数据盘快照，保留 7 天；删除源盘时保留快照。
  - 风险：仅保留 7 天。缓解：可按需调大 `max_retention_days`，成本线性增加。

- `mig.tf`
  - 实例模板（Spot）：
    - e2-medium、Debian 12、引导盘 50GB（自删除）、外网 IP 仅用于出站（无入站规则）。
    - 启用 Shielded VM、OS Login、阻止项目级 SSH Key；安装 Docker。
    - 调度：`provisioning_model = SPOT`，`instance_termination_action = STOP`，不自动重启。
  - 托管实例组（MIG）：
    - 单可用区目标规模 `mig_size=2`（提高抗回收能力，结合 Cloudflare 免费版仍在预算内），被回收时自动补齐。
  - 风险：
    - 无健康检查会降低自愈的准确性。缓解：保持目标规模，本阶段不引入 LB，避免固定费用；后续可加自建健康探针与脚本再滚动替换。
    - Spot 随时回收。缓解：仅部署无状态服务；数据在核心 VM。

- `outputs.tf`
  - 输出核心 VM 的公网 IP、备份桶名与 MIG 名称。

---

## 已采取的风险缓解措施（在编写中已落实）
- 成本控制：
  - 不创建外部负载均衡，避免固定月费；只暴露核心 VM 的 80/443。
  - MIG 使用 Spot 实例，自动补齐但无固定成本。
- 安全：
  - MIG 通过防火墙显式拒绝所有入站；仅允许必要的核心 VM 端口。
  - 启用 Shielded VM、OS Login、阻止项目级 SSH Key 继承。
  - 备份桶按桶级授权，最小权限到对象写入。
- 数据持久化与备份：
  - 核心 VM 使用独立数据盘 + 每日快照（7 天）。
  - 如 gcloud 可用，追加每日逻辑备份到 GCS；双重冗余。

---

## 后续可选优化（保持预算内的前提）
- 将 `allow_source_ranges` 限制为固定办公出口 IP；或引入 Cloudflare/WAF（会增加少量成本）。
- Cloudflare 建议：
  - DNS 代理（橙云开启）到核心 VM 公网 IP；SSL 模式设为 Full（Strict），在核心 VM 使用 Origin CA 或 Let’s Encrypt。
  - 打开 Managed Rules（Pro 版）与 Rate Limiting（视计划），并按业务接口增加限频规则。
  - 若计划切换到仅 HTTPS，Cloudflare 上强制 HTTPS；在 GCP 防火墙可移除 80 端口。
- 在核心 VM 上启用 Fail2ban、自动安全更新（unattended-upgrades）。
- 为 MIG 增加启动脚本：从核心 VM 拉取最新 env 与镜像标签，统一版本；增加守护脚本监控容器并自动重启。
- 备份保留策略细化（例如全量 + 增量），或延长保留期（成本增加可控）。


