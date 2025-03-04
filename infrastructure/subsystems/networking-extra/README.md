# Networking Extra

This module provides advanced networking capabilities through DNS filtering, VPN connectivity, and network infrastructure management.

## Quick Links

<a href="https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/tunnel-guide/" target="_blank"><img src="../../../.static/images/logos/cloudflared.png" width="32" height="32" alt="Cloudflared"></a> <a href="https://pi-hole.net/" target="_blank"><img src="../../../.static/images/logos/pi-hole.svg" width="32" height="32" alt="Pi-hole"></a> <a href="https://tailscale.com/" target="_blank"><img src="../../../.static/images/logos/tailscale.png" width="32" height="32" alt="Tailscale"></a> <a href="https://nlnetlabs.nl/documentation/unbound/" target="_blank"><img src="../../../.static/images/logos/unbound.png" width="32" height="32" alt="Unbound"></a> <a href="https://ui.com/" target="_blank"><img src="../../../.static/images/logos/unifi.svg" width="32" height="32" alt="UniFi"></a>

## Overview

The networking-extra module provides three main capabilities:

1. DNS Management
   - Secure DNS resolution chain:
     - Pi-hole for ad blocking and filtering
     - Cloudflared for DNS-over-HTTPS (1.1.1.2/1.0.0.2)
     - Unbound for local DNSSEC validation
   - Security features:
     - DNSSEC validation
     - Query logging and monitoring
     - Privacy-focused configuration
     - Cache optimization
   - Performance tuning:
     - Aggressive NSEC caching
     - QNAME minimization
     - Prefetching support

2. VPN Connectivity
   - Tailscale integration:
     - Operator-based deployment
     - Custom hostname support
     - API server proxy capability
     - Zero-trust network access
   - Security features:
     - MagicDNS support
     - WireGuard encryption
     - Identity-based access

3. Network Management
   - UniFi Network Application:
     - Device discovery and adoption
     - Network monitoring
     - Configuration management
     - Firmware updates
   - Service ports:
     - L2 discovery (UDP 1900)
     - Device adoption (TCP 8080)
     - STUN (UDP 3478)
     - DNS (TCP/UDP 53)
     - NTP (UDP 123)
     - Remote syslog (UDP 5514)
     - Speed test (TCP 6789)
     - Management UI (TCP 8443)

### Component Architecture

```mermaid
flowchart TB
    %% Color scheme
    classDef dns fill:#a7f3d0,stroke:#059669,color:#064e3b
    classDef vpn fill:#bfdbfe,stroke:#3b82f6,color:#1e3a8a
    classDef mgmt fill:#fecaca,stroke:#dc2626,color:#7f1d1d
    classDef storage fill:#fde68a,stroke:#d97706,color:#92400e
    classDef infra fill:#e5e7eb,stroke:#6b7280,color:#374151
    classDef client fill:#f5d0fe,stroke:#c026d3,color:#701a75
    classDef legend fill:none,stroke:none,color:#6b7280

    %% Clients
    subgraph clients[" "]
        direction LR
        local-clients(["Local DNS Clients"]):::client
        k8s-apps(["Kubernetes Apps"]):::client
        network-devices(["Network Devices"]):::client
        vpn-clients(["VPN Clients"]):::client
        style clients fill:none,stroke:none
    end

    %% External Services
    external["Cloudflare DNS<br/>1.1.1.2/1.0.0.2"]:::infra
    root["Root DNS<br/>DNSSEC Chain"]:::infra
    local["Local DNS Records"]:::infra

    %% DNS Services
    subgraph dns["DNS Services"]
        direction TB
        pihole["Pi-hole<br/>Ad Blocking & Filtering"]:::dns
        cloudflared["Cloudflared<br/>DNS-over-HTTPS"]:::dns
        unbound["Unbound<br/>DNSSEC Resolver"]:::dns
        coredns["CoreDNS<br/>Kubernetes DNS"]:::dns
    end

    %% Network Services
    subgraph network["Network Services"]
        direction TB
        unifi-router["UniFi Router<br/>Local DNS Resolution"]:::mgmt
    end

    %% VPN Components
    subgraph vpn["VPN Access"]
        direction TB
        tailscale["Tailscale Operator<br/>Zero Trust VPN"]:::vpn
    end

    %% Network Management
    subgraph mgmt["Network Management"]
        direction TB
        unifi["UniFi Network Application<br/>Device & Network Control"]:::mgmt
        mongodb["MongoDB<br/>Configuration Store"]:::mgmt
    end

    %% Storage
    subgraph storage["Persistent Storage"]
        direction TB
        unifi-data["UniFi Data PVC"]:::storage
        unifi-backup["UniFi Backup PVC"]:::storage
        mongodb-data["MongoDB Data PVC"]:::storage
        pihole-data["Pi-hole Data PVC"]:::storage
    end

    %% DNS Resolution Flow
    %% Local clients to Pi-hole
    local-clients --> pihole
    pihole --> cloudflared
    pihole --> unbound
    pihole --> unifi-router
    cloudflared --> external
    unbound --> root
    unifi-router --> local

    %% Kubernetes DNS resolution
    k8s-apps --> coredns
    coredns --> pihole
    coredns --> unifi-router

    %% UniFi Flow
    network-devices --> unifi
    unifi --> mongodb
    unifi --> unifi-data
    unifi --> unifi-backup

    %% MongoDB Storage
    mongodb --> mongodb-data

    %% Pi-hole Storage
    pihole --> pihole-data

    %% VPN Flow
    vpn-clients -.-> tailscale

    %% Legend
    subgraph Legend[" "]
        direction LR
        client-l["Clients"]:::client
        dns-l["DNS Services"]:::dns
        vpn-l["VPN Services"]:::vpn
        mgmt-l["Management"]:::mgmt
        storage-l["Storage"]:::storage
        infra-l["External Services"]:::infra
        style Legend fill:none,stroke:none
    end
```

### Component Details

| Component | Primary Role | Integration Points |
|-----------|-------------|-------------------|
| Pi-hole | DNS filtering | • Blocks ads and malware<br>• Integrates with cloudflared for DoH<br>• Provides query statistics<br>• Uses persistent storage for config |
| Cloudflared | DNS-over-HTTPS | • Connects to Cloudflare DNS<br>• Uses malware-blocking resolvers<br>• Exposes metrics endpoint<br>• Supports connection pooling |
| Unbound | DNS resolution | • Performs DNSSEC validation<br>• Implements privacy features<br>• Optimizes caching<br>• Supports prefetching |
| Tailscale | VPN access | • Manages network access<br>• Supports custom hostnames<br>• Enables API server proxy<br>• Zero-trust architecture |
| UniFi | Network management | • Controls network devices<br>• Manages configurations<br>• Handles firmware updates<br>• Collects device statistics |

## Prerequisites

1. Required Components

   | Component | Purpose | Configuration |
   |-----------|---------|---------------|
   | MongoDB | UniFi database | From database-core |
   | Storage | Persistent data | From storage-core |
   | Certificates | TLS termination | From security-core |

2. Required Variables

   | Variable | Purpose | Example |
   |----------|---------|---------|
   | domain_name | DNS zone | example.com |
   | dns_zone | Internal zone | homelab.local |
   | dns_fallback | Backup DNS | 1.1.1.1 |
   | pihole_external_ip_address | Pi-hole IP | 192.168.1.53 |

3. Required Secrets

   | Secret Name | Purpose | Required Keys |
   |-------------|---------|---------------|
   | pihole-secrets | Pi-hole admin | pihole_password |
   | unifi-secrets | UniFi database | unifi_db_user, unifi_db_password |
   | tailscale-auth | VPN access | authkey |

## Dependencies

### Required By

- Application modules requiring:
  - DNS filtering and security
  - VPN access
  - Network management

### Depends On

- [networking-core](../networking-core) - For basic networking
- [security-core](../security-core) - For certificates
- [storage-core](../storage-core) - For persistence

## Usage

### DNS Configuration

```yaml
# Example: Configure DNS-over-HTTPS
apiVersion: v1
kind: ConfigMap
metadata:
  name: cloudflared-config
  namespace: pihole
data:
  config.yml: |
    proxy-dns: true
    proxy-dns-port: 53
    proxy-dns-upstream:
      - https://1.1.1.2/dns-query
      - https://1.0.0.2/dns-query
```

### VPN Access

```yaml
# Example: Configure Tailscale subnet router
apiVersion: tailscale.com/v1alpha1
kind: Tailscale
metadata:
  name: subnet-router
spec:
  hostname: "k8s-subnet-router"
  authKey:
    secretRef:
      name: tailscale-auth
      key: authkey
  routes:
    - "10.0.0.0/8"
```

### Network Management

```yaml
# Example: Configure UniFi device adoption
apiVersion: v1
kind: Service
metadata:
  name: unifi-controller
  annotations:
    metallb.universe.tf/allow-shared-ip: "true"
spec:
  type: LoadBalancer
  ports:
  - name: device-comm
    port: 8080
    protocol: TCP
  - name: discovery
    port: 10001
    protocol: UDP
```
