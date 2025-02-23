# Downloaders Subsystem

Integrated media management solution enabling automated downloading and organization of movies, TV shows, music, and subtitles.

## Quick Links

- [Radarr Documentation](https://github.com/Radarr/Radarr)
- [Sonarr Documentation](https://github.com/Sonarr/Sonarr)
- [Lidarr Documentation](https://github.com/lidarr/Lidarr)
- [Prowlarr Documentation](https://github.com/Prowlarr/Prowlarr)
- [SABnzbd Documentation](https://github.com/sabnzbd/sabnzbd)
- [Recyclarr Documentation](https://github.com/recyclarr/recyclarr)

## Overview

The downloaders subsystem consists of three main capability groups:

1. Media Management
   - Automated organization of movies, TV shows, and music
   - Subtitle management and synchronization
   - User request handling and tracking
   - Library maintenance and cleanup

2. Download Management
   - Centralized indexer configuration
   - Usenet download handling
   - Automated quality profiles
   - Download state tracking

3. Configuration Management
   - Automated service configuration
   - Quality profile synchronization
   - Release profile management
   - Custom format definitions

### Component Architecture

The following diagram illustrates how the various components of the downloaders subsystem work together to provide comprehensive media management capabilities. It shows the flow of requests, metadata, and content between services, as well as their interaction with shared infrastructure.

```mermaid
flowchart TB
    %% Color scheme with good contrast for light/dark themes
    classDef media fill:#a7f3d0,stroke:#059669,color:#064e3b
    classDef download fill:#bfdbfe,stroke:#3b82f6,color:#1e3a8a
    classDef config fill:#fecaca,stroke:#dc2626,color:#7f1d1d
    classDef infra fill:#e5e7eb,stroke:#4b5563,color:#1f2937
    classDef request fill:#fde68a,stroke:#d97706,color:#92400e
    classDef legend fill:none,stroke:none,color:#6b7280

    %% Media Management Services
    radarr[Radarr<br/>Movies]:::media
    sonarr[Sonarr<br/>TV Shows]:::media
    lidarr[Lidarr<br/>Music]:::media
    bazarr[Bazarr<br/>Subtitles]:::media

    %% Download Infrastructure
    prowlarr[Prowlarr<br/>Indexers]:::download
    sabnzbd[SABnzbd<br/>Downloads]:::download

    %% Configuration Management
    recyclarr[Recyclarr<br/>Config Sync]:::config

    %% Request Management
    overseerr[Overseerr<br/>Requests]:::request

    %% Shared Infrastructure
    subgraph infrastructure[Shared Infrastructure]
        direction TB
        postgres[(PostgreSQL<br/>Databases)]:::infra
        storage[(Shared Media<br/>Storage)]:::infra
    end

    %% Request Flow
    overseerr --> radarr
    overseerr --> sonarr

    %% Media Management Flow
    radarr --> prowlarr
    sonarr --> prowlarr
    lidarr --> prowlarr

    radarr --> sabnzbd
    sonarr --> sabnzbd
    lidarr --> sabnzbd

    bazarr --> radarr
    bazarr --> sonarr

    %% Storage Access
    sabnzbd --> storage
    radarr --> storage
    sonarr --> storage
    lidarr --> storage
    bazarr --> storage

    %% Database Access
    radarr -.-> postgres
    sonarr -.-> postgres
    lidarr -.-> postgres
    bazarr -.-> postgres
    prowlarr -.-> postgres
    overseerr -.-> postgres

    %% Configuration Management
    recyclarr --> radarr
    recyclarr --> sonarr
    recyclarr --> lidarr

    %% Simple legend at bottom
    subgraph Legend[" "]
        direction LR
        media_leg[Media Management]:::media
        download_leg[Download Services]:::download
        config_leg[Configuration]:::config
        request_leg[Request Management]:::request
        infra_leg[Infrastructure]:::infra
    end

    %% Styling
    class Legend legend
    class infrastructure legend
```

<sup>*Line styles: Solid (→) = Application communication (API calls, downloads), Dotted with arrow (-.→) = Database connections*</sup>

### Component Details

| Component | Type | Primary Role | Key Features | Integration Points |
|-----------|------|--------------|--------------|-------------------|
| Radarr | Media Manager | Movie Management | • Comprehensive movie library organization<br>• Advanced quality profile management<br>• Intelligent release filtering<br>• State persistence in PostgreSQL | • Searches content through Prowlarr's indexer network<br>• Automatically sends download tasks to SABnzbd<br>• Receives configuration updates from Recyclarr |
| Sonarr | Media Manager | TV Series Management | • Complete TV series tracking<br>• Automated season/episode management<br>• Smart media file renaming<br>• State persistence in PostgreSQL | • Searches content through Prowlarr's indexer network<br>• Automatically sends download tasks to SABnzbd<br>• Receives configuration updates from Recyclarr |
| Lidarr | Media Manager | Music Management | • Comprehensive music library organization<br>• Detailed artist/album tracking<br>• Advanced quality profiles<br>• State persistence in PostgreSQL | • Searches content through Prowlarr's indexer network<br>• Automatically sends download tasks to SABnzbd<br>• Receives configuration updates from Recyclarr |
| Bazarr | Media Manager | Subtitle Management | • Automated subtitle downloading<br>• Multi-language management<br>• Intelligent subtitle synchronization<br>• State persistence in PostgreSQL | • Actively monitors Radarr/Sonarr media libraries<br>• Directly manages subtitle files in media storage |
| Overseerr | Media Manager | Request Management | • User-friendly request interface<br>• Comprehensive request tracking<br>• Integrated library discovery<br>• State persistence in PostgreSQL | • Forwards movie/TV requests to Radarr/Sonarr<br>• Integrates with external authentication systems |
| Prowlarr | Download Service | Indexer Management | • Centralized indexer configuration<br>• Unified search API for all services<br>• Detailed statistics tracking<br>• State persistence in PostgreSQL | • Processes search requests from all *arr services<br>• Manages indexer API keys and capabilities<br>• Continuously monitors indexer health status |
| SABnzbd | Download Service | Download Client | • Full Usenet download management<br>• Intelligent post-processing<br>• Priority-based download handling<br>• Pre-optimized configuration | • Processes download requests from *arr services<br>• Handles extraction and cleanup of downloads<br>• Reports detailed download status to services |
| Recyclarr | Configuration Service | Config Management | • Automated daily configuration sync<br>• Comprehensive profile management<br>• Scheduled updates (18:00 UTC)<br>• Custom format definitions | • Maintains consistent configuration across *arr services<br>• Manages quality definitions and scoring<br>• Updates custom format specifications |

## Prerequisites

1. Persistent Storage

   | PVC Name | Purpose | Access Mode |
   |----------|---------|-------------|
   | media | Shared media storage | RWX |
   | radarr-data | Radarr configuration | RWX |
   | sonarr-data | Sonarr configuration | RWX |
   | lidarr-data | Lidarr configuration | RWX |
   | bazarr-data | Bazarr configuration | RWX |
   | prowlarr-data | Prowlarr configuration | RWX |
   | overseerr-data | Overseerr configuration | RWX |
   | sabnzbd-data | SABnzbd configuration | RWX |

2. Required Secrets

   | Secret Name | Purpose | Required Keys |
   |-------------|---------|---------------|
   | downloaders-db-app | Database access | username, password |
   | downloader-api-keys | Service API keys | radarr_api_key, sonarr_api_key, etc. |

3. Required Variables

   | Variable | Purpose | Used By |
   |----------|---------|---------|
   | MEDIA_WRITER_UID | File ownership | All services |
   | MEDIA_WRITER_GID | File ownership | All services |
   | POSTGRES_DB_SIZE | Database storage | PostgreSQL |
   | POSTGRES_DB_STORAGE_CLASS | Database storage | PostgreSQL |
