# Application Modules

This directory contains application modules that provide end-user functionality on top of the cluster's infrastructure capabilities. Each module delivers specific user-facing services while leveraging the platform's core services for security, storage, and operations.

## Functional Areas & Capabilities

| Category | Functional Areas | Module Capabilities |
| --- | --- | --- |
| AI | Language Models<br/>Chat Interfaces<br/>AI Gateway<br/>Workflow Automation | [ai](./subsystems/ai):<br/>• Provides web-based chat via <a href="https://github.com/open-webui/open-webui" target="_blank">OpenWebUI</a>, backed by a self-hosted LiteLLM gateway<br/>• Routes cloud model traffic through a self-hosted <a href="https://github.com/BerriAI/litellm" target="_blank">LiteLLM</a> gateway with automatic provider failover, virtual key/budget management, and request caching<br/>• Exposes self-hosted MCP servers for documentation lookup, browser automation, observability, Kubernetes, network, and home automation to any gateway client<br/>• Supports conversation history management<br/>• Automates glue workflows via a self-hosted <a href="https://n8n.io" target="_blank">n8n</a> instance (own namespace/Postgres) — Alertmanager, *arr, and email integrations<br/>• Provides a WhatsApp-reachable conversational front door via OpenClaw (own namespace, hardened), able to trigger n8n workflows and relay results back |
| Security & Credentials | Password Management<br/>Secrets Storage<br/>Identity Management | [bitwarden](./subsystems/bitwarden):<br/>• Provides <a href="https://bitwarden.com/help/password-manager-overview/" target="_blank">end-to-end encrypted password vault</a> with zero-knowledge architecture<br/>• Enables credential autofill in browsers and mobile apps with browser extensions<br/>• Supports two-factor authentication and secure password generation<br/>• Integrates with enterprise SSO and directory systems |
| Development Tools | Remote Development<br/>Cloud Workspaces<br/>IDE Support | [coder](./subsystems/coder):<br/>• Creates <a href="https://coder.com/docs/about" target="_blank">cloud-based development environments</a> with any IDE (VS Code, JetBrains, Web)<br/>• Provides server-grade compute resources for faster development<br/>• Enables consistent environments through infrastructure tools (Terraform, Docker)<br/>• Supports secure remote access through HTTPS/SSH |
| Container Registry | Image Management<br/>Security Scanning<br/>Access Control | [harbor](./subsystems/harbor):<br/>• Stores and manages <a href="https://github.com/goharbor/harbor/blob/main/README.md" target="_blank">container images and Helm charts</a> with role-based access<br/>• Performs vulnerability scanning on container images with policy enforcement<br/>• Enables image signing and content trust through Notary<br/>• Provides automated garbage collection and image cleanup |
| Home Automation | Device Control<br/>Automation<br/>Monitoring | [home-automation](./subsystems/home-automation):<br/>• Integrates with smart home devices through <a href="https://www.home-assistant.io/" target="_blank">Home Assistant</a><br/>• Provides automation engine for device control based on triggers and conditions<br/>• Enables custom dashboards for monitoring and control<br/>• Supports local processing without cloud dependencies |
| Media Management | Media Servers<br/>Content Organization<br/>Collection Management<br/>Download Management | [media](./subsystems/media):<br/>• Streams media through <a href="https://www.plex.tv/" target="_blank">Plex</a> (transcoding, user management) and Jellyfin<br/>• Enables privacy-focused YouTube viewing through <a href="https://freetubeapp.io/" target="_blank">FreeTube</a><br/>• Monitors Plex statistics and usage through <a href="https://tautulli.com/" target="_blank">Tautulli</a><br/>• Manages Plex collections and home screen curation through <a href="https://github.com/agregarr/agregarr" target="_blank">Agregarr</a><br/><br/>[downloaders](./subsystems/downloaders):<br/>• Automates IRC/RSS torrent grabbing through <a href="https://autobrr.com/" target="_blank">autobrr</a><br/>• Manages TV shows through <a href="https://github.com/Sonarr/Sonarr/blob/v5-develop/README.md" target="_blank">Sonarr</a> with quality profiles and metadata<br/>• Handles movies through <a href="https://github.com/Radarr/Radarr/blob/develop/README.md" target="_blank">Radarr</a> with automated organization<br/>• Manages music through <a href="https://github.com/Lidarr/Lidarr/blob/develop/README.md" target="_blank">Lidarr</a> with artist monitoring<br/>• Provides unified indexer management through <a href="https://github.com/Prowlarr/Prowlarr/blob/develop/README.md" target="_blank">Prowlarr</a><br/>• Processes Usenet downloads via <a href="https://sabnzbd.org/wiki/" target="_blank">SABnzbd</a> with repair and extraction<br/>• Processes BitTorrent downloads via <a href="https://github.com/qbittorrent/qBittorrent" target="_blank">qBittorrent</a> with VPN routing<br/>• Manages qBittorrent and cross-seeds torrents through <a href="https://getqui.com/" target="_blank">qui</a><br/>• Handles media requests through <a href="https://github.com/seerr-team/seerr" target="_blank">Seerr</a> with Plex/Jellyfin/Emby integration |
| Misc Services | Email Relay<br/>Specialized Tools | [misc](./subsystems/misc):<br/>• Houses miscellaneous applications that don't require dedicated modules<br/>• Provides SMTP relay services through <a href="https://github.com/foxcpp/maddy" target="_blank">Maddy</a><br/>• Supports both implicit and explicit TLS for secure email transmission |

## Module Relationships

The following diagram shows how application modules depend on infrastructure capabilities:

```mermaid
flowchart BT
    %% Color scheme - infrastructure less prominent than apps
    classDef infra fill:#e2e8f0,stroke:#64748b,color:#475569
    classDef apps fill:#93c5fd,stroke:#2563eb,color:#1e3a8a
    classDef universal fill:none,stroke:#64748b
    classDef appbox fill:none,stroke:#2563eb
    classDef invisible fill:none,stroke:none

    %% Universal Infrastructure Layer
    subgraph UniversalDeps["Universal Dependencies"]
        direction TB
        security[security-core]:::infra
        storage[storage-core]:::infra
        networking[networking-core]:::infra
        observability[observability-core]:::infra
    end
    class UniversalDeps universal

    %% Database (specific dependency)
    database[database-core]:::infra

    %% Apps Layer with visible border
    subgraph Apps["Application Modules"]
        direction TB
        coder[coder]:::apps
        downloaders[downloaders]:::apps
        home-automation[home-automation]:::apps
        ai[ai]:::apps
        bitwarden[bitwarden]:::apps
        harbor[harbor]:::apps
        media[media]:::apps
        misc[misc]:::apps
    end
    class Apps appbox

    %% Universal Dependencies (every app) with thicker arrow from connection point
    Apps ====> UniversalDeps

    %% Specific Database Dependencies
    coder --> database
    downloaders --> database
    home-automation --> database
    ai --> database
```

## Configuration

For detailed information about configuration methods used across all modules, including Kustomize patches, FluxCD post-build variables, and component overlays, refer to the [Configuration Methods](../projectBrief.md#configuration-methods) section in the project brief.
