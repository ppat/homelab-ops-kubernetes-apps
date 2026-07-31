# AI Subsystem

Self-hosted AI platform providing a web interface for interacting with AI models routed through a self-hosted LLM gateway, self-hosted MCP tooling, and a shared knowledge vault that both the operator and every AI client can read and contribute to.

## Quick Links

<a href="https://www.litellm.ai" target="_blank"><img src="../../../.static/images/logos/litellm.svg" width="32" height="32" alt="LiteLLM"></a> <a href="https://n8n.io" target="_blank"><img src="../../../.static/images/logos/n8n.svg" width="32" height="32" alt="n8n"></a> <a href="https://obsidian.md" target="_blank"><img src="../../../.static/images/logos/obsidian.svg" width="32" height="32" alt="Obsidian"></a> <a href="https://github.com/openclaw/openclaw" target="_blank"><img src="../../../.static/images/logos/openclaw.svg" width="32" height="32" alt="OpenClaw"></a> <a href="https://github.com/open-webui/open-webui" target="_blank"><img src="../../../.static/images/logos/open-webui.png" width="32" height="32" alt="OpenWebUI"></a>

## Overview

The AI subsystem consists of six main capability groups:

1. User Interface
   - Web-based chat interface
   - Model selection and configuration
   - Conversation history management
   - Optional external LLM integration

2. AI Gateway
   - Unified routing across multiple LLM providers, with automatic failover
   - Virtual key, team, and budget management for gateway consumers
   - Request caching and cost tracking

3. MCP Tooling
   - Self-hosted MCP servers exposing documentation lookup, browser automation, observability, Kubernetes, network, home automation, and GitHub tools to any client behind the gateway

4. Workflow Automation
   - Self-hosted n8n instance (own namespace, own Postgres) for glue workflows between the LLM gateway, MCP servers, Alertmanager, the *arr stack, and email
   - Owner-login authenticated; not part of the shared SSO/forward-auth layer yet

5. Conversational Gateway
   - OpenClaw provides a WhatsApp-reachable conversational front door (own namespace), able to trigger n8n workflows and relay results back
   - Locked down hard: read-only MCP access, no exec/browser/elevated tools, pairing-only DMs — see [Prerequisites](#prerequisites) for the full list of what's disabled day-one

6. Knowledge Vault
   - A git-backed markdown vault (own namespace, `obsidian-vault`) that AI clients write to and the operator reads, backed by a headless in-cluster Obsidian instance
   - Headless Obsidian is the only process that mounts vault content read-write and the only one that ever mutates a markdown file
   - Two separately-scoped MCP server instances of the same image are the only network door to it — one confined to the agent capture zones, one carrying the wider scope promotion requires
   - Isolated by a default-deny-ingress namespace where only the gateway may reach the MCP servers and only the MCP servers may reach Obsidian
   - No ingress at all: the Obsidian GUI is reachable solely by `kubectl port-forward` — see [Notes](#notes)

## Component Architecture

The following diagram illustrates how the AI subsystem components work together, showing the relationship between the web interface, the LLM gateway, and how users interact with the system.

```mermaid
flowchart TB
    %% Color scheme with good contrast for light/dark themes
    classDef core fill:#a7f3d0,stroke:#059669,color:#064e3b
    classDef ui fill:#bfdbfe,stroke:#3b82f6,color:#1e3a8a
    classDef gateway fill:#fbcfe8,stroke:#db2777,color:#831843
    classDef storage fill:#d8b4fe,stroke:#9333ea,color:#581c87
    classDef external fill:#fde68a,stroke:#d97706,color:#92400e
    classDef legend fill:none,stroke:none,color:#6b7280

    %% External Access
    user[User]:::external
    whatsapp[WhatsApp]:::external
    cloud[Cloud LLMs]:::external
    githubremote[GitHub<br/>ppat/obsidian-vault]:::external
    nasremote[NAS<br/>bare repo mirror]:::external

    %% Core Components - Module Provided
    subgraph module[AI Module]
        openwebui[OpenWebUI Interface]:::ui
        litellm[LiteLLM Gateway]:::gateway
        context7[context7 MCP Server]:::core
        github[GitHub MCP Server]:::core
        playwright[Playwright MCP Server]:::core
        grafana[Grafana MCP Server]:::core
        kubehomelab[Kubernetes MCP Server<br/>homelab cluster]:::core
        kubenas[Kubernetes MCP Server<br/>nas cluster]:::core
        homeassistant[Home Assistant MCP Server]:::core
        unifinetwork[UniFi Network MCP Server]:::core
        unifiprotect[UniFi Protect MCP Server]:::core
        n8n[n8n Automation<br/>ns: n8n]:::ui
        openclaw[OpenClaw Gateway<br/>ns: openclaw]:::ui
        subgraph vault[Knowledge Vault — ns: obsidian-vault]
            mcpagent[Obsidian MCP Server<br/>agent-scoped]:::core
            mcpingestor[Obsidian MCP Server<br/>ingestor-scoped]:::core
            obsidian[Headless Obsidian<br/>+ Local REST API]:::ui
            gitcommitter[Git Committer<br/>CronJob]:::core
        end
    end

    %% Storage Components - Dependencies
    subgraph storage[Storage Dependencies]
        openwebui_pvc[(PVC: openwebui)]:::storage
        litellm_db[("PostgreSQL<br/>Database")]:::storage
        litellm_cache[("Redis-compatible<br/>Cache")]:::storage
        n8n_db[("PostgreSQL<br/>Database (n8n)")]:::storage
        openclaw_pvc[(PVC: openclaw-data)]:::storage
        vault_pvc[(PVC: vault-data)]:::storage
        vault_git_pvc[(PVC: vault-git-cache)]:::storage
    end

    %% Relationships
    user --> openwebui
    user --> n8n
    whatsapp <--> openclaw

    openwebui --> litellm
    n8n --> litellm
    openclaw --> litellm
    litellm -.-> cloud

    litellm --> context7
    litellm --> github
    litellm --> playwright
    litellm --> grafana
    litellm --> kubehomelab
    litellm --> kubenas
    litellm --> homeassistant
    litellm --> unifinetwork
    litellm --> unifiprotect
    litellm -->|agent handle| mcpagent
    litellm -->|ingestor handle| mcpingestor
    mcpagent --> obsidian
    mcpingestor --> obsidian
    openclaw -.->|read-only MCP| litellm

    openclaw -->|triggers| n8n
    n8n -->|relays via hooks| openclaw

    openwebui --> openwebui_pvc
    litellm --> litellm_db
    litellm --> litellm_cache
    n8n --> n8n_db
    openclaw --> openclaw_pvc
    obsidian --> vault_pvc
    user -.->|port-forward, GUI only| obsidian

    gitcommitter -.->|read-only, scheduled| vault_pvc
    gitcommitter --> vault_git_pvc
    gitcommitter -.->|push, scheduled| githubremote
    gitcommitter -.->|push, scheduled| nasremote
```

<!-- markdownlint-disable-next-line MD036 -->
<sup>*Line styles: Solid (→) = Direct interaction, Dotted (-.→) = Optional connection*</sup>

### Component Details

| Component | Type | Primary Role | Key Features | Integration Points |
| ----------- | ------ | -------------- | -------------- | ------------------- |
| OpenWebUI | Core | Web Interface | • User-friendly chat interface<br>• Conversation management<br>• Model selection and configuration<br>• Cloud LLM integration via the LiteLLM gateway | • LiteLLM gateway integration for cloud model access<br>• Direct user access via web browser<br>• Persistent storage for settings |
| LiteLLM | Gateway | AI Gateway | • Unified routing across multiple LLM providers with automatic failover<br>• Virtual key, team, and budget management<br>• Request caching and cost tracking<br>• Hosts MCP servers for client tool access | • OpenWebUI and other gateway consumer integration<br>• PostgreSQL for persistent configuration and spend data<br>• Redis-compatible cache for response caching<br>• mcp-context7, mcp-github, mcp-grafana, mcp-home-assistant, mcp-kubernetes-homelab, mcp-kubernetes-nas, mcp-obsidian-agent, mcp-obsidian-ingestor, mcp-playwright, mcp-unifi-network, and mcp-unifi-protect integration |
| mcp-context7 | Core | Documentation MCP Server | • Self-hosted library/API documentation lookup<br>• MCP protocol interface for AI clients<br>• Stateless, lightweight process | • Hosted behind the LiteLLM gateway<br>• Provides documentation context to AI assistants |
| mcp-github | Core | GitHub MCP Server | • Self-hosted `github/github-mcp-server`, read-broad with a narrow, explicit `--tools` allowlist for writes<br>• Writes limited to issue create/update, issue and PR comments, sub-issue linking, PR review-thread replies, and gist creation<br>• Holds no GitHub credential of its own — LiteLLM injects the PAT as a bearer token on every call<br>• MCP protocol interface for AI clients | • Hosted behind the LiteLLM gateway, which supplies the bearer-token PAT<br>• Provides GitHub issue/PR/repository/search/security-alert context and limited write tools to AI assistants |
| mcp-grafana | Core | Observability MCP Server | • Self-hosted Grafana MCP server covering search, dashboards, datasources, Prometheus, Loki, alerting, navigation, and panel queries, plus write access<br>• Admin toolset excluded<br>• Service-account token self-provisioned and rotated via an ESO `Grafana` generator authenticating with Grafana admin basic auth, so it survives a Grafana DB wipe with no manual re-pasting<br>• MCP protocol interface for AI clients | • Hosted behind the LiteLLM gateway<br>• Connects to the in-cluster Grafana instance, both for its API calls and to mint its own service-account token<br>• Provides observability context and query tools to AI assistants |
| mcp-home-assistant | Core | Home Automation MCP Server | • Self-hosted Home Assistant MCP server<br>• Read-write access for device control and automation<br>• MCP protocol interface for AI clients | • Hosted behind the LiteLLM gateway<br>• Connects to the in-cluster Home Assistant instance<br>• Provides home automation control and inspection tools to AI assistants |
| mcp-kubernetes-homelab | Core | Kubernetes Cluster MCP Server (homelab) | • Self-hosted, read-only Kubernetes cluster MCP server for the homelab cluster<br>• Explicit read-only allow-list, plus a `denied_resources` entry blocking Secrets as defence-in-depth<br>• MCP protocol interface for AI clients | • Hosted behind the LiteLLM gateway<br>• In-cluster access via a dedicated ServiceAccount, bound (outside this module) to a purpose-built read-only ClusterRole the consuming cluster provides<br>• Provides cluster state context to AI assistants |
| mcp-kubernetes-nas | Core | Kubernetes Cluster MCP Server (nas) | • Self-hosted, read-only Kubernetes cluster MCP server for the separate `nas` cluster<br>• Reaches that cluster via a mounted kubeconfig (`cluster_provider_strategy = "kubeconfig"`) rather than in-cluster credentials<br>• Same read-only allow-list and Secrets-denial posture as the homelab server<br>• MCP protocol interface for AI clients | • Hosted behind the LiteLLM gateway on the homelab cluster (kept behind the gateway even though its target cluster is remote)<br>• Kubeconfig sourced from the `kubeconfig_nas_mcp` secret-store key<br>• Provides nas cluster state context to AI assistants |
| mcp-obsidian-agent | Core | Knowledge Vault MCP Server (agent scope) | • Self-hosted `cyanheads/obsidian-mcp-server` in the `obsidian-vault` namespace, fronting the headless Obsidian REST API<br>• Writes confined to the agent capture zones (`00-inbox/`, `40-journal/`, `_ops/agent/`) plus the root `log.md`; reads span the whole vault<br>• Path matching is prefix-based with implicit recursion and applies across every tool, note deletion included<br>• Command-palette tools disabled at the server, not merely withheld at the gateway<br>• Authenticates callers with a JWT, unlike the `auth_type: none` posture of every other MCP server here | • Hosted behind the LiteLLM gateway as the `obsidian_agent_mcp` server; only the LiteLLM pod may reach it<br>• Calls the in-cluster `obsidian` Service over HTTPS with the Local REST API bearer token<br>• The write door for OpenClaw, n8n, Claude Code, and the drift-reconciliation channel |
| mcp-obsidian-ingestor | Core | Knowledge Vault MCP Server (ingestor scope) | • Second instance of the same image, carrying the wider write scope promotion, lint, and bulk ingest require<br>• Curated areas, the raw layer, the archive, and the `_ops` records are writable here and nowhere else<br>• The schema file, the hand-curated index, templates, and `.obsidian/` stay outside every write scope<br>• A separate instance rather than a second gateway handle onto the agent instance — a shared instance would leak this scope to the narrower handle | • Hosted behind the LiteLLM gateway as the `obsidian_ingestor_mcp` server; only the LiteLLM pod may reach it<br>• Calls the same in-cluster `obsidian` Service<br>• Reserved for the vault worker and batch processor, never agent-facing keys |
| mcp-playwright | Core | Browser Automation MCP Server | • Self-hosted browser automation and web interaction<br>• MCP protocol interface for AI clients<br>• Headless browser execution | • Hosted behind the LiteLLM gateway<br>• Provides browsing/automation tools to AI assistants |
| mcp-unifi-network | Core | UniFi Network MCP Server | • Self-hosted, read-only UniFi Network MCP server<br>• MCP protocol interface for AI clients | • Hosted behind the LiteLLM gateway<br>• Connects to the UniFi Network controller<br>• Provides network state context to AI assistants |
| mcp-unifi-protect | Core | UniFi Protect MCP Server | • Self-hosted, read-only UniFi Protect MCP server<br>• MCP protocol interface for AI clients | • Hosted behind the LiteLLM gateway<br>• Connects to the UniFi Protect controller<br>• Provides camera/security system context to AI assistants |
| n8n | Core | Workflow Automation | • Self-hosted n8n (main mode, own namespace/Postgres)<br>• Owner-login authenticated, LAN/tailnet-only ingress<br>• Alertmanager/*arr/Harbor/Coder webhook receivers<br>• Transactional and workflow email via Maddy SMTP | • Calls the LiteLLM gateway for model access and MCP tools<br>• Triggers OpenClaw's `/hooks/agent` to relay results to WhatsApp<br>• Own CloudNativePG PostgreSQL cluster for workflow/credential storage |
| Obsidian | Core | Knowledge Vault Engine | • Headless Obsidian with the Local REST API plugin baked in and auto-trusted (own namespace, `obsidian-vault`)<br>• The only workload mounting vault content read-write, and the only process that ever mutates a markdown file<br>• Non-root, read-only root filesystem, `Recreate` rollout so two instances never hold the vault at once<br>• ClusterIP only, no ingress; readiness is the REST API answering, which proves the vault is open, trusted, and the plugin loaded<br>• GUI reachable on demand by `kubectl port-forward` against the same running process | • Reached only by the two Obsidian MCP servers, enforced by NetworkPolicy<br>• Mounts the externally-provisioned `vault-data` PVC, holding only the vault's markdown content — Obsidian's own app state (vault registration, plugin-trust flag) lives on an ephemeral emptyDir, not this claim<br>• Bearer token for its REST API is pinned from the secret store so the MCP servers can be wired declaratively |
| git-committer | Core | Vault Git Committer | • Scheduled `CronJob`, not a long-lived Deployment — takes a commit and exits, so it holds a mount on `vault-data` only while a commit is actually being taken rather than adding a third permanent attachment<br>• Mounts `vault-data` read-only and writes only to its own git-dir PVC, never vault content<br>• Pushes the same derived history to a GitHub remote and a NAS bare-repo mirror over SSH, with host-key verification pinned rather than disabled<br>• `concurrencyPolicy: Forbid`, so an in-flight `git push` is never killed mid-run by the next scheduled tick | • Reads the `vault-data` PVC read-only; Obsidian is the only other mounter, and its mount is read-write — the two MCP servers never touch this PVC, they reach Obsidian over its REST API<br>• Own `vault-git-cache` PVC for git's own metadata, kept off the vault volume entirely<br>• SSH deploy key (`git-committer-secrets`) authorized as a write key on the GitHub remote and in the NAS's `authorized_keys` |
| OpenClaw | Core | Conversational Gateway | • WhatsApp-reachable conversational front door (own namespace)<br>• Hardened: read-only MCP, no exec/browser/elevated tools, pairing-only DMs<br>• Inbound hooks for n8n/Alertmanager relays, daily cron digest | • Calls the LiteLLM gateway for model access (cheap model set)<br>• Read-only MCP via LiteLLM `/mcp` and direct Home Assistant MCP (read-only toolFilter)<br>• Triggers n8n workflows and relays their output back to WhatsApp |

## Prerequisites

This module also depends on a PostgreSQL and Redis-compatible cache, provisioned via the cluster's database operators, for the LiteLLM gateway's configuration, spend tracking, and response caching. n8n has its own dedicated PostgreSQL cluster (own namespace, own postBuild variables — see below).

n8n, OpenClaw, and the knowledge vault each run in their own isolated namespace (`n8n`, `openclaw`, `obsidian-vault`) rather than the shared `ai` namespace. Neither ingress is behind SSO forward-auth yet (deferred — requires coordinated Terraform-repo changes); n8n relies on its own owner login, OpenClaw on its gateway auth token. Both are LAN/tailnet-only, same as the rest of this module.

OpenClaw's runtime config (`openclaw.json`, delivered as the `openclaw-config` ConfigMap in the `openclaw` namespace), its `openclaw-config-secrets` Secret, and its `openclaw-data` PVC are all cluster-provided — like `litellm-model-config`, this module mounts them but does not ship them. The image's entrypoint wrapper seeds `openclaw.json` into a writable path (`chmod 600`) at startup, so the module carries no `openclaw.json` of its own.

1. Persistent Storage

   | PVC Name | Purpose | Access Mode |
   | -------- | ------- | ----------- |
   | vault-data | Authoritative knowledge-vault content — the markdown files themselves, not Obsidian's own app state | RWX |
   | vault-git-cache | The git committer's own repository metadata (its `--git-dir`) — never vault content, and never mounted by any other workload | RWO |
   | openwebui | User settings and conversation history | RWX |
   | n8n-data | n8n configuration, workflow static data | RWO |
   | openclaw-data | OpenClaw config, workspace, memory SQLite, and WhatsApp Baileys session | RWO |

   All five PVCs are provisioned externally (by the cluster), not defined by this module. `vault-data` is RWX because it has two read-only consumers beyond Obsidian itself: the git committer delivered by this phase, and a still-pending maintenance worker from a later phase, both of which must mount it without being co-scheduled onto the Obsidian pod's node. `vault-git-cache` is RWO — `concurrencyPolicy: Forbid` on the git committer's CronJob means at most one pod ever holds it at a time, and nothing else in this module mounts it.

2. Required Secrets

   | Secret Name | Purpose | Required Keys |
   | ----------- | ------- | -------------- |
   | litellm-openwebui-key | OpenWebUI's virtual key for authenticating to the LiteLLM gateway — sourced from the `apikey_litellm_openwebui` secret-store key, which is populated by a separate Terraform-managed workspace, not manually | apikey |
   | n8n-secrets | n8n's encryption key, pre-provisioned owner login (email + password hash), pre-seeded LiteLLM/SMTP credential-overwrite blob, its LiteLLM virtual key, and SMTP relay credentials + sender | N8N_ENCRYPTION_KEY, N8N_INSTANCE_OWNER_EMAIL, N8N_INSTANCE_OWNER_PASSWORD_HASH, N8N_CREDENTIALS_OVERWRITE_DATA, LITELLM_API_KEY, N8N_SMTP_USER, N8N_SMTP_PASS, N8N_SMTP_SENDER |
   | openclaw-secrets | OpenClaw's universal secrets — gateway auth token and LiteLLM virtual key | OPENCLAW_GATEWAY_TOKEN, LITELLM_KEY |
   | openclaw-config-secrets | Feature-coupled OpenClaw secrets — inbound hooks bearer token and owner WhatsApp number (used by `channels.whatsapp.allowFrom`). Provided by the cluster, co-located with the cluster-owned `openclaw.json`; not shipped by this module | OPENCLAW_HOOKS_TOKEN, OWNER_WHATSAPP_NUMBER |
   | obsidian-secrets | Pins the Local REST API plugin's bearer token, so it is a known value rather than one generated inside the running container | OBSIDIAN_API_KEY |
   | mcp-obsidian-agent-secrets | The same REST API bearer token the agent-scoped MCP server spends on callers' behalf, plus the signing secret it verifies inbound JWTs against | OBSIDIAN_API_KEY, MCP_AUTH_SECRET_KEY |
   | mcp-obsidian-ingestor-secrets | The same, for the ingestor-scoped MCP server; its signing secret is deliberately distinct from the agent instance's | OBSIDIAN_API_KEY, MCP_AUTH_SECRET_KEY |
   | git-committer-secrets | One SSH keypair's private key, used for both push remotes, plus the pinned host keys the committer verifies against instead of trusting either remote on first connection. The public half must be registered as a write deploy key on the GitHub remote and dropped into the NAS's `authorized_keys` — both out of band, not by this module | ssh-privatekey, known_hosts |

   The following secret-store keys are also required by the LiteLLM gateway and its self-hosted MCP servers:

   | Secret Store Key | Purpose |
   | ------------------- | --------- |
   | litellm_master_key | LiteLLM proxy master/admin API key |
   | litellm_salt_key | Encryption salt for virtual keys persisted in LiteLLM's database |
   | apikey_openrouter_litellm | OpenRouter API key used by LiteLLM to route requests to OpenRouter-hosted models |
   | litellm_redis_password | Password for LiteLLM's Redis-compatible cache |
   | apikey_context7_mcp | context7 API key required by the self-hosted mcp-context7 server |
   | github_pat_mcp | Fine-grained GitHub PAT that LiteLLM injects as a bearer token when calling mcp-github; the server itself holds no credential |
   | cluster_homelab_grafana_admin_password | Grafana admin-user password (the same one observability-core provisions for `grafana-admin-credentials`), used by mcp-grafana's ESO `Grafana` generator to authenticate via admin basic auth and self-provision its own Editor-role service-account token |
   | unifi_network_username_mcp | Username for a native UniFi Read-Only/Viewer account, used by the self-hosted mcp-unifi-network server |
   | unifi_network_password_mcp | Password for the UniFi Network account used by the self-hosted mcp-unifi-network server |
   | unifi_protect_username_mcp | Username for a UniFi Protect View-Only account, used by the self-hosted mcp-unifi-protect server |
   | unifi_protect_password_mcp | Password for the UniFi Protect account used by the self-hosted mcp-unifi-protect server |
   | homeassistant_token_mcp | Long-lived Home Assistant access token (from an admin user) used by the self-hosted mcp-home-assistant server |
   | kubeconfig_nas_mcp | Kubeconfig for the remote `nas` cluster, mounted into the self-hosted mcp-kubernetes-nas server so it can reach that cluster's API |
   | n8n_encryption_key | n8n's data-at-rest encryption key (credentials, etc.) — must not change after first boot |
   | n8n_owner_password_hash | bcrypt hash of the n8n owner account password, used to pre-provision the owner login and skip the setup wizard |
   | n8n_credentials_overwrite | JSON blob n8n loads via `N8N_CREDENTIALS_OVERWRITE_DATA` to pre-seed the LiteLLM (OpenAI-compatible) and Maddy SMTP credentials matched by name against example workflows supplied at the cluster level and imported at rollout (not shipped in this module) |
   | apikey_litellm_n8n | n8n's virtual key for authenticating to the LiteLLM gateway |
   | n8n_smtp_user | Username n8n authenticates with against the Maddy SMTP relay |
   | n8n_smtp_password | Password n8n authenticates with against the Maddy SMTP relay |
   | n8n_owner_email | Email address of the pre-provisioned n8n owner account (sourced into `N8N_INSTANCE_OWNER_EMAIL`) |
   | n8n_smtp_sender | From/sender address n8n sets on outbound mail — must be an address the SMTP account is authorized to send as (sourced into `N8N_SMTP_SENDER`) |
   | openclaw_gateway_token | Bearer token required to reach OpenClaw's control UI/gateway |
   | apikey_litellm_openclaw | OpenClaw's virtual key for authenticating to the LiteLLM gateway |
   | openclaw_hooks_token | Bearer token n8n/Alertmanager present when calling OpenClaw's inbound `/hooks/agent` endpoint |
   | openclaw_owner_whatsapp_number | Owner's E.164 WhatsApp number, the only sender OpenClaw's `pairing` DM policy admits without a pairing code |
   | obsidian_rest_api_key | Bearer token for the Local REST API plugin inside headless Obsidian. Pinned into the Obsidian pod and held by both Obsidian MCP servers; a caller holding it can write anywhere in the vault, since the REST layer has no path-scoped permissions of its own |
   | obsidian_agent_mcp_auth_secret | Shared secret (minimum 32 characters) the agent-scoped MCP server verifies inbound JWTs against |
   | obsidian_ingestor_mcp_auth_secret | The same for the ingestor-scoped MCP server. Deliberately a different value, so an agent token cannot be replayed against the wider-scoped instance |
   | obsidian_agent_mcp_jwt | Pre-minted JWT signed with `obsidian_agent_mcp_auth_secret`, which LiteLLM presents as a bearer token when calling the agent-scoped server |
   | obsidian_ingestor_mcp_jwt | Pre-minted JWT signed with `obsidian_ingestor_mcp_auth_secret`, for the ingestor-scoped server |
   | obsidian_git_committer_ssh_private_key | The git committer's SSH private key. One key, used for both the GitHub and NAS push remotes — not a per-remote credential pair |
   | obsidian_git_committer_known_hosts | Pinned host keys for both push remotes, so the committer can keep strict host-key checking on instead of trusting either host on first connection |

3. Required Variables

   | Variable | Purpose | Used By |
   | ---------- | --------- | --------- |
   | domain_name | External access URL (openwebui.${domain_name}) and UniFi controller host (unifi.nodes.${domain_name}) | OpenWebUI, mcp-unifi-network, mcp-unifi-protect |
   | dns_zone | Private-registry domain the git committer's image is pulled from (`harbor.nas.${dns_zone}`) | git-committer |
   | git_committer_remote_origin_url | SSH URL of the GitHub remote the committer pushes derived history to | git-committer |
   | git_committer_remote_nas_url | SSH URL of the NAS bare-repository mirror the committer pushes the same history to | git-committer |
   | grafana_admin_username | Grafana admin username mcp-grafana's ESO generator authenticates with to self-provision its service-account token. Optional, defaults to `admin` | mcp-grafana |
   | db_name | PostgreSQL cluster name prefix | LiteLLM |
   | db_suffix_current | PostgreSQL cluster name suffix (blue/green rotation) | LiteLLM |
   | db_bootstrap_database | Initial database name created on bootstrap | LiteLLM |
   | db_bootstrap_owner | Initial database owner role created on bootstrap | LiteLLM |
   | db_replicas | PostgreSQL instance count | LiteLLM |
   | db_storage_size | PostgreSQL volume size | LiteLLM |
   | db_storage_class | PostgreSQL volume storage class | LiteLLM |
   | n8n_db_name | n8n's PostgreSQL cluster name prefix (own var — kept separate from `db_name` so the two clusters in this shared module never collide) | n8n |
   | n8n_db_suffix_current | n8n's PostgreSQL cluster name suffix (blue/green rotation) | n8n |
   | n8n_db_bootstrap_database | Initial database name created on bootstrap (default `n8n`) | n8n |
   | n8n_db_bootstrap_owner | Initial database owner role created on bootstrap (default `n8n`) | n8n |
   | n8n_db_replicas | n8n PostgreSQL instance count | n8n |
   | n8n_db_storage_size | n8n PostgreSQL volume size | n8n |
   | n8n_db_storage_class | n8n PostgreSQL volume storage class | n8n |
   | n8n_owner_first_name | First name of the pre-provisioned n8n owner account (default `Admin`) | n8n |
   | n8n_owner_last_name | Last name of the pre-provisioned n8n owner account (default `User`) | n8n |

4. Optional Configuration

   | ConfigMap Name | Namespace | Key | Purpose |
   | --------------- | --------- | ---- | ------- |
   | litellm-model-config | ai | model-config.yaml | Model catalog and routing tuning (`proxy_config.model_list`, `router_settings.fallbacks`/`routing_strategy`/`allowed_fails`/`cooldown_time`) for the LiteLLM gateway. Not provided by this module — merged in via the HelmRelease's `spec.valuesFrom` (optional). Without it, LiteLLM falls back to the chart's own built-in placeholder models. |

5. RBAC

   | Resource | Access | Purpose |
   | -------- | ------ | ------- |
   | ClusterRole: `mcp-kubernetes-readonly` — homelab cluster (**not shipped by this module**; a prerequisite the consuming cluster must provide, e.g. `clusters/<cluster>/cluster/rbac/mcp-kubernetes-readonly.yaml` in the clusters repo) | Purpose-built, explicit read-only allow-list, cluster-wide, excluding Secrets | Bound (in the consuming cluster's own manifests) to the `mcp-kubernetes-homelab` ServiceAccount this module ships |
   | ClusterRole: `mcp-kubernetes-readonly` — nas cluster (**not shipped by this module**; must exist on the remote `nas` cluster itself) | Purpose-built, explicit read-only allow-list, cluster-wide, excluding Secrets | Bound to the identity presented by mcp-kubernetes-nas's mounted kubeconfig |

## Notes

- **mcp-github credential and write boundary**: mcp-github is the only MCP component in this module with no `secrets.yaml`/ExternalSecret of its own — in `http` mode, `github-mcp-server` has no server-side-token option, so auth is strictly bearer pass-through and the PAT lives only in `litellm-secrets`, injected by LiteLLM as `Authorization: Bearer` on every call; the mcp-github pod holds no GitHub credential. Correspondingly, `github_mcp` is the only `mcp_servers` entry in the LiteLLM config with a non-`none` `auth_type`. The write boundary is enforced by the `--tools` allowlist on the mcp-github Deployment, not by LiteLLM config: the server is read-broad, with writes limited to issue create/update, issue and PR comments, sub-issue linking, PR review-thread replies, and gist creation. This allowlist is deliberately not mirrored into LiteLLM's `allowed_tools`, to avoid two sources of truth for the same boundary.
- **mcp-kubernetes-homelab / mcp-kubernetes-nas access posture**: both run against an explicit read-only allow-list ClusterRole (`mcp-kubernetes-readonly`), not the built-in `view` role, and that ClusterRole is cluster policy, not module behaviour — this module ships only the `mcp-kubernetes-homelab` ServiceAccount that role gets bound to on the homelab cluster. mcp-kubernetes-nas has no ServiceAccount of its own (`automountServiceAccountToken: false`); it authenticates entirely via its mounted kubeconfig, so the same ClusterRole must be bound to that kubeconfig's identity on the remote `nas` cluster. Secrets are excluded twice over on both servers: by the ClusterRole itself, and again by a `denied_resources` entry in each server's `config.toml` as defence-in-depth. external-secrets kinds (e.g. `ExternalSecret`, `ClusterSecretStore`) are readable under this allow-list — their specs reference secret-store keys by name and never contain secret values.
- **MCP tool access control and boundary**: access control for MCP tools is enforced by **LiteLLM virtual-key scoping**, configured out-of-band in the LiteLLM UI (eventually Terraform) and therefore not visible in this repo. Registering a new MCP server does not, by itself, grant existing keys access to it — each virtual key that should reach the new server must be deliberately updated to include it. At the network level, the `mcp-servers-ingress` NetworkPolicy (`network-policy.yaml`) restricts ingress to the MCP Services to the LiteLLM pod (plus Prometheus in `monitoring`, for future scraping) by selecting on the `app.kubernetes.io/component: mcp-server` label — this is what makes the LiteLLM gateway an enforced access boundary for the MCP Services rather than just a convention, and is also why n8n reaches MCP servers through LiteLLM rather than allowlisting them directly (see `N8N_SSRF_ALLOWED_HOSTNAMES` in `n8n/deployment.yaml`). Enforcement depends on the cluster's CNI implementing NetworkPolicy — k3s does, via its bundled network policy controller, unless the cluster runs with `--disable-network-policy`.
- **`app.kubernetes.io/component: mcp-server` pod label**: every MCP server Deployment's pod template (not its immutable `spec.selector`) carries this label, giving every MCP server a single stable selector the `mcp-servers-ingress` NetworkPolicy targets regardless of `app.kubernetes.io/name`. It exists so a server added later by copying an existing module directory is covered by that policy by default rather than silently unprotected. The two Obsidian MCP servers carry the same label in the `obsidian-vault` namespace, where it selects both the policy admitting LiteLLM inbound and the policy admitting them onward to Obsidian.

- **`obsidian-vault/` nests one level deeper than the rest of this module**: every other component sits directly under the module root (`litellm/`, `mcp-*/`, `n8n/`, `openclaw/`), while the three vault services (`obsidian/`, `mcp-obsidian-agent/`, `mcp-obsidian-ingestor/`) sit under `obsidian-vault/`. That is deliberate — everything under it shares one namespace and one network posture, and the module already carries a dozen top-level entries. The extra level is what makes the namespace boundary visible in the directory tree; flattening it back would hide it.

- **Single-writer invariant**: exactly one process ever writes the vault's files — headless Obsidian. Every writer in the system (OpenClaw over WhatsApp, scheduled n8n jobs, Claude Code, later a batch processor, a maintenance worker, and a drift-reconciliation channel) is a client of that one door, never a second filesystem writer. Two things in the manifests enforce it structurally rather than by convention: the Obsidian Deployment uses `Recreate` (a rolling update would run two Obsidian processes against the same volume mid-rollout), and it is the only workload that mounts `vault-data` read-write. This phase adds the first of two planned read-only mounts of that claim — the git committer — with a still-pending maintenance worker to follow in a later phase.

- **git-committer is a CronJob, not a Deployment** — deliberately, not by default. A long-lived committer would leave two questions open that a Deployment can't answer for itself: what rollout strategy it should use, and whether it needs the descheduler `prefer-no-eviction` annotation the Obsidian Deployment carries. Both questions presuppose a pod that outlives a single unit of work; a CronJob has neither a rollout nor anything to evict between runs, so it doesn't answer those questions, it removes them. It also *narrows* the multi-attach exposure noted above rather than adding to it: `clusters#799` observed `AttachVolume.Attach` succeed for a second Obsidian pod two seconds after that pod was already marked for deletion during a pod-template flap, meaning the single-writer invariant currently holds by timing more than by enforcement. A long-lived committer would be a third permanent attachment on `vault-data` and a second pod template capable of flapping; a CronJob holds a mount on that PVC only while a commit is actually being taken. See `ppat/homelab-ops-kubernetes-apps#3443` and `ppat/obsidian-tools#3`.

- **git-committer's `concurrencyPolicy` diverges from this repo's only other CronJob.** `apps/subsystems/downloaders/recyclarr/cronjob.yaml` uses `Replace`, which is correct for an idempotent Recyclarr sync but wrong here: `Replace` kills the currently-running Job outright to start the next tick's, and the running Job could be mid `git push`. git-committer uses `Forbid` instead, which skips a tick that would overlap a still-running one rather than killing it.

- **Network isolation in `obsidian-vault` is the sole control, not defence in depth**: the `obsidian-vault` namespace runs default-deny ingress, which the `ai` namespace deliberately does not. The reason is specific to what sits behind it. The Local REST API in front of Obsidian offers no path-scoped permissions of its own — any caller reaching it can write anywhere in the vault — and it additionally exposes a second, unscoped MCP endpoint at `/mcp/` that upstream provides no way to disable: no such setting exists, it registers unconditionally whenever the REST server is enabled, and the upstream request to split it into a separate plugin was closed the same day with no change. The `obsidian-ingress` NetworkPolicy is therefore the *only* thing standing in front of that endpoint. Its failure is an open door onto the whole vault, not a hardening regression — which is also why it carries no Prometheus exception, unlike `mcp-obsidian-ingress` and the `ai` namespace's policy. As elsewhere, enforcement depends on the cluster's CNI implementing NetworkPolicy, and `kind` does not — so CI can only assert the policies' shape, never that they bite.

- **Two MCP instances, not two gateway handles**: a LiteLLM virtual key decides *who* may call; an MCP server instance's `OBSIDIAN_WRITE_PATHS` decides *where* a write may land. These are separate axes, and the module runs two instances of the same image rather than pointing two gateway handles at one. An instance does not know which handle called it, so two handles onto a shared instance would each see that instance's entire write scope — whoever held the narrow handle would get the wide one's reach for free. Separate instances make the wider scope physically unreachable through the narrower handle, independent of gateway configuration. The two also hold separate JWT signing secrets, so a leaked agent token cannot be replayed against the ingestor.

- **Obsidian MCP auth diverges from the rest of this module**: every other MCP server here is registered with `auth_type: none` and relies on the ingress NetworkPolicy alone. Both Obsidian servers run `MCP_AUTH_MODE=jwt` and are registered with `auth_type: bearer_token` (the same non-`none` shape `github_mcp` uses, for a different reason). The difference is what sits behind them: the listener binds `0.0.0.0`, and an unauthenticated caller reaching it would have the vault's REST API bearer token spent on its behalf. Per-tool scope checks are switched off on both servers, which upstream documents as the supported posture when the caller cannot inject per-request claims — LiteLLM sends one static token per server, so a scope claim in it could not distinguish one client from another anyway. That distinction is made by per-client virtual-key tool filtering at the gateway; authorisation at the server is `OBSIDIAN_WRITE_PATHS`, which no token can widen. Signature, audience, issuer and expiry validation are unaffected.

- **Per-client vault access scope**: as with every other MCP server here, virtual keys are managed out-of-band at runtime and appear in no repository, so no code review can catch an over-scoped key. This table is therefore the durable record of the intended scoping, and folder-level path scoping at the server is the backstop that makes an out-of-band key tolerable — a key broader than intended still cannot write outside the paths its instance permits. Destructive and command-execution tools (note deletion, command-palette execution) are absent from every agent-facing key entirely, not merely scoped away from curated folders; the command-palette pair is additionally disabled at both servers.

  | Client | Handle | Tools |
  | ------ | ------ | ----- |
  | n8n | agent | Read/search, narrow frontmatter status updates, and appends to `log.md` only |
  | OpenClaw | agent | Read/search, create-in-inbox, append, patch, frontmatter, tags |
  | Claude Code | agent | As OpenClaw, plus section and structural edits |
  | Open WebUI | agent | Read/search only — human-facing chat, and the human is not a writer |
  | Vault worker | ingestor | Read/search, patch, frontmatter, append, move/promote |
  | Batch processor | ingestor | The same as the vault worker |

  Write paths follow the instance, not the key: the agent handle can only ever land a write in `00-inbox/`, `40-journal/`, `_ops/agent/`, or `log.md`; the ingestor handle additionally reaches `05-raw/`, `10-areas/`, `20-projects/`, `90-archive/`, and the rest of `_ops/`. Matching is prefix-based with implicit recursion rather than glob, so `00-inbox/` covers everything beneath it, and a bare filename such as `log.md` is a valid degenerate prefix matching only itself. Batch runs disable the agent handle and leave the ingestor handle live.

- **The Obsidian GUI is deliberately reachable, and deliberately ungated**: configuring Obsidian itself — property types, default location for new notes, attachment folder, daily-note format, template folder — requires its GUI, and the only alternative is hand-crafting undocumented application config. So the GUI stays available: a VNC server ships in the image but is never started, and is attached on demand to the display the already-running Obsidian process owns, reached by `kubectl port-forward`. There is no ingress and no second GUI-bearing deployment, because two Obsidian processes against one volume would break the single-writer invariant. A human writing at that GUI carries none of the MCP path's controls — no validation, no provenance stamping, and no record that a write happened until a later maintenance pass notices it. Tolerable for occasional configuration and repair, corrosive as a habit.

- **Obsidian image is pinned by digest, not exercised by CI**: the Obsidian Deployment points at a published, digest-pinned `docker.io/ppatlabs/obsidian` reference rather than a bare tag, because the upstream image is rebuilt and its tags reused — a bare tag would silently change what runs, and this container is the single writer to the authoritative vault. CI does not exercise this container beyond applying and server-side-validating it: the boot chain (Xvfb, Electron, a DevTools attach that disables Restricted Mode) is untested against `kind`'s resource envelope, and how it should be validated there is an open question, tracked in #3440.
