# Networking Core

This module provides foundational networking capabilities for the cluster, enabling load balancing, DNS management, and ingress control. It allows services to be exposed externally, manages DNS records automatically, and provides secure ingress traffic handling.

## Quick Links

- [MetalLB Documentation](https://metallb.universe.tf/)
- [ExternalDNS Documentation](https://github.com/kubernetes-sigs/external-dns)
- [Traefik Documentation](https://doc.traefik.io/traefik/)

## Overview

The networking-core module provides three main capabilities:

1. Load Balancing
   - Layer 2 network load balancing
   - IP address pool management
   - Service type LoadBalancer support
   - Automatic IP address allocation

2. DNS Management
   - Automated DNS record synchronization
   - Support for PiHole and UniFi DNS providers
   - Service and ingress record creation
   - DNS record ownership management

3. Ingress Control
   - TLS termination (minimum TLS 1.2)
   - Built-in middlewares for HTTPS redirection and header management
   - JSON format access logging
   - Ingress and CRD support

### Component Details

| Component | Primary Role | Integration Points |
|-----------|-------------|-------------------|
| MetalLB | Layer 2 load balancing | • Allocates IP addresses from configured pools to LoadBalancer services<br>• Announces service IPs using Layer 2 mode for local network visibility<br>• Enables external access for cluster services that require it<br> |
| ExternalDNS | DNS record automation | • Watches services and ingresses for DNS record annotations<br>• Synchronizes DNS records with configured provider (PiHole or UniFi)<br>• Manages record lifecycle based on service/ingress presence<br>• Supports TXT ownership records for conflict prevention (UniFi only) |
| Traefik | Ingress controller | • Routes external traffic to appropriate services based on rules<br>• Manages TLS certificates from security-core for HTTPS<br>• Provides middlewares for HTTPS redirection and header management<br>• Exposes services through configured entrypoints |

## Prerequisites

1. Required Variables

   | Variable | Purpose | Required By |
   |----------|---------|-------------|
   | domain_name | Domain for ingress endpoints | Traefik, ExternalDNS |
   | metallb_standard_ip_pool | IP range for service allocation | MetalLB |
   | externaldns_provider | DNS provider selection (pihole/unifi) | ExternalDNS |
   | dns_zone | DNS zone for UniFi controller | ExternalDNS (UniFi only) |

2. Required Secrets

   | Secret Name | Purpose | Required Keys |
   |-------------|---------|---------------|
   | external-dns-secrets | DNS provider authentication | For PiHole: pihole_password<br>For UniFi: unifi_username, unifi_password |

3. DNS Provider Requirements
   - PiHole:
     - PiHole web interface accessible at pihole-web.pihole.svc.cluster.local
     - Admin password for PiHole API access
   - UniFi:
     - UniFi controller accessible at unifi.homelab.${dns_zone}
     - User credentials with DNS management permissions
     - External controller access enabled

## Dependencies

### Required By

- [networking-extra](../networking-extra)
- [observability-core](../observability-core)
- Application modules requiring external access

### Depends On

- [security-core](../security-core)
