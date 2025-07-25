# Media Subsystem

Media streaming and management platform providing multiple specialized services with hardware-accelerated transcoding support.

## Quick Links

 <a href="https://freetubeapp.io/" target="_blank"><img src="../../../.static/images/logos/freetube.svg" width="32" height="32" alt="FreeTube"></a> <a href="https://jellyfin.org/" target="_blank"><img src="../../../.static/images/logos/jellyfin.svg" width="32" height="32" alt="Jellyfin"></a> <a href="https://www.plex.tv/" target="_blank"><img src="../../../.static/images/logos/plex.svg" width="32" height="32" alt="Plex"></a> <a href="https://tautulli.com/" target="_blank"><img src="../../../.static/images/logos/tautulli.svg" width="32" height="32" alt="Tautulli"></a>

## Overview

The media subsystem consists of three main capability groups:

1. Media Streaming
   - Multiple streaming server options
   - Hardware-accelerated transcoding
   - Client auto-discovery
   - Format compatibility

2. Media Management
   - Library organization
   - Metadata management
   - User preferences
   - Playback history

3. Analytics and Alternative Media
   - Streaming analytics
   - Usage statistics
   - Privacy-focused alternatives
   - Performance monitoring

### Component Details

| Component | Type | Primary Role | Key Features | Integration Points |
|-----------|------|--------------|--------------|-------------------|
| Jellyfin | Core | Media Server | • Hardware-accelerated transcoding with Intel GPU<br>• Comprehensive library organization and metadata<br>• Advanced multi-user access control<br>• Automatic client discovery and streaming | • Direct access to shared media storage<br>• State persistence in PostgreSQL database<br>• Hardware integration with Intel GPU for transcoding |
| Plex | Core | Media Server | • Hardware-accelerated transcoding with Intel GPU<br>• Rich metadata management and matching<br>• Sophisticated multi-user system<br>• Smart client auto-discovery | • Seamless access to shared media storage<br>• Efficient Intel GPU transcoding pipeline<br>• Optional external authentication system |
| Tautulli | Supporting | Analytics Platform | • Detailed streaming usage analytics<br>• Comprehensive user activity monitoring<br>• In-depth library statistics<br>• Real-time performance tracking | • Deep integration with Plex server monitoring<br>• Long-term historical data retention<br>• Detailed analytics processing |
| FreeTube | Supporting | Media Client | • Privacy-respecting YouTube frontend<br>• Secure local subscription management<br>• Complete ad-free experience<br>• Independent media playback | • Self-contained operation without tracking<br>• Direct media streaming without intermediaries<br>• Local data management |

## Prerequisites

1. Node Requirements

   | Requirement | Purpose | Notes |
   |------------|---------|--------|
   | Node Label | Transcoding support | Label: `intel.feature.node.kubernetes.io/gpu: "true"` |
   | Intel GPU | Hardware transcoding | Required for Plex and Jellyfin |

2. Persistent Storage

   | PVC Name | Purpose | Access Mode | Notes |
   |----------|---------|-------------|--------|
   | media-read-only | Media library | RWX | Shared between all services |
   | plex-data | Plex configuration | RWX | Plex server state |
   | plex-logs | Plex logs | RWX | Plex logs |
   | jellyfin-data | Jellyfin configuration | RWX | Jellyfin server state |
   | jellyfin-logs | Jellyfin logs | RWX | Jellyfin logs |

3. Required Variables

   | Variable | Purpose | Used By |
   |----------|---------|----------|
   | plex_external_ip_address | External access URL | Plex ADVERTISE_IP |
   | jellyfin_external_ip_address | External access URL | Jellyfin PublishedServerUrl |

4. Required Secrets

   | Secret Name | Purpose | Required Keys |
   |-------------|---------|---------------|
   | plex-secrets | Plex configuration | Optional, service-specific |
