# Networking Core

This module provides foundational networking capabilities for the cluster, enabling load balancing, DNS management, and ingress control. It allows services to be exposed externally, manages DNS records automatically, and provides secure ingress traffic handling.

## Quick Links

<a href="https://github.com/kubernetes-sigs/external-dns" target="_blank"><img src="../../../.static/images/logos/kubernetes.svg" width="32" height="32" alt="ExternalDNS"></a> <a href="https://metallb.io/" target="_blank"><img src="../../../.static/images/logos/metallb.png" width="32" height="32" alt="MetalLB"></a> <a href="https://traefik.io/" target="_blank"><img src="../../../.static/images/logos/traefik.svg" width="32" height="32" alt="Traefik"></a>

## Overview

The networking-core module provides three main capabilities:

1. Load Balancing
   - Layer 2 network load balancing
   - IP address pool management
   - Service type LoadBalancer support
   - Automatic IP address allocation

2. DNS Management
   - Automated DNS record synchronization
   - UniFi DNS provider, through a webhook
   - Service and ingress record creation
   - DNS record ownership management

3. Ingress Control
   - TLS termination (minimum TLS 1.2)
   - Built-in middlewares for HTTPS redirection and header management
   - JSON format access logging
   - Ingress and CRD support

### Component Details

| Component | Primary Role | Integration Points |
| ----------- | ------------- | ------------------- |
| MetalLB | Layer 2 load balancing | • Allocates IP addresses from configured pools to LoadBalancer services<br>• Announces service IPs using Layer 2 mode for local network visibility<br>• Enables external access for cluster services that require it<br> |
| ExternalDNS | DNS record automation | • Watches services and ingresses for DNS record annotations<br>• Synchronizes DNS records with the UniFi controller through the unifi webhook provider<br>• Manages record lifecycle based on service/ingress presence<br>• Supports TXT ownership records for conflict prevention |
| Traefik | Ingress controller | • Routes external traffic to appropriate services based on rules<br>• Manages TLS certificates from security-core for HTTPS<br>• Provides middlewares for HTTPS redirection and header management<br>• Exposes services through configured entrypoints |

## Prerequisites

1. Required Variables

   | Variable | Purpose | Required By |
   | ---------- | --------- | ------------- |
   | domain_name | Domain for ingress endpoints | Traefik, ExternalDNS |
   | metallb_standard_ip_pool | IP range for service allocation | MetalLB |
   | dns_zone | DNS zone for UniFi controller | ExternalDNS |

2. Required Secrets

   | Secret Name          | Purpose                     | Required Keys |
   |----------------------|-----------------------------|---------------|
   | external-dns-secrets | DNS provider authentication | unifi_apikey  |

3. DNS Provider Requirements
   - The [external-dns-provider/unifi](../../../components/external-dns-provider/unifi) component, layered on through `spec.components`. It supplies the provider values through ConfigMap `external-dns-provider-config`, which the external-dns HelmRelease requires
   - UniFi controller accessible at unifi.nodes.${dns_zone}
   - UniFi API key with DNS management permissions

## Dependencies

### Required By

- [networking-extra](../networking-extra)
- [observability-core](../observability-core)
- Application modules requiring external access

### Depends On

- [security-core](../security-core)
