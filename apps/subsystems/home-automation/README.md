# Home Automation Subsystem

Home automation platform centered around Home Assistant, enabling integration with various IoT protocols and devices through a secure MQTT messaging infrastructure, with voice control capabilities through local speech-to-text and text-to-speech processing.

## Quick Links

<a href="https://www.home-assistant.io/" target="_blank"><img src="../../../.static/images/logos/home-assistant.svg" width="32" height="32" alt="Home Assistant"></a> <a href="https://github.com/emqx/nanomq" target="_blank"><img src="../../../.static/images/logos/nanomq.png" width="32" height="32" alt="NanoMQ"></a> <a href="https://github.com/coder/code-server" target="_blank"><img src="../../../.static/images/logos/vscode.svg" width="32" height="32" alt="Code Server"></a>

## Overview

The home-automation subsystem consists of three main capability groups:

1. Automation Platform
   - Home automation control and monitoring
   - Device state management
   - Automation rules and scripts
   - Web-based configuration interface

2. Message Infrastructure
   - MQTT broker for device communication
   - Multi-protocol support (MQTT, WebSocket, HTTP)
   - Secure authentication and access control
   - IoT protocol integration support

3. Voice Capabilities
   - Local speech-to-text processing
   - Local text-to-speech synthesis
   - Voice command recognition
   - Voice response generation

### Component Architecture

The following diagram illustrates how the home automation subsystem components work together, including external services that integrate through the MQTT broker. While the external services are not part of this subsystem, they are shown to demonstrate the complete integration architecture.

```mermaid
flowchart TB
    %% Color scheme with good contrast for light/dark themes
    classDef hub fill:#a7f3d0,stroke:#059669,color:#064e3b
    classDef messaging fill:#bfdbfe,stroke:#3b82f6,color:#1e3a8a
    classDef external fill:#fecaca,stroke:#dc2626,color:#7f1d1d
    classDef infra fill:#e5e7eb,stroke:#4b5563,color:#1f2937
    classDef dev fill:#fde68a,stroke:#d97706,color:#92400e
    classDef voice fill:#d8b4fe,stroke:#7e22ce,color:#581c87
    classDef legend fill:none,stroke:none,color:#6b7280

    %% Message Broker
    nanomq[NanoMQ<br/>MQTT Broker]:::messaging

    %% Voice Components
    piper[Wyoming Piper<br/>Text-to-Speech]:::voice
    whisper[Wyoming Whisper<br/>Speech-to-Text]:::voice

    %% Hub Components
    homeassistant[Home Assistant<br/>Core Platform]:::hub
    code[Code Server<br/>Configuration IDE]:::dev

    %% External Services
    subgraph external["External Services (Not in this module)"]
        direction TB
        zwave[Z-Wave JS UI<br/>Z-Wave Integration]:::external
        zigbee[Zigbee2MQTT<br/>Zigbee Integration]:::external
        ble[BLE2MQTT<br/>Bluetooth Integration]:::external
    end

    %% Shared Infrastructure
    subgraph infrastructure[Shared Infrastructure]
        direction TB
        postgres[(PostgreSQL<br/>Database)]:::infra
        ha_storage[(Configuration<br/>Storage)]:::infra
        piper_storage[(Piper<br/>Storage)]:::infra
        whisper_storage[(Whisper<br/>Storage)]:::infra
    end

    %% MQTT Communication
    homeassistant --> nanomq
    zwave --> nanomq
    zigbee --> nanomq
    ble --> nanomq

    %% Voice Component Communication
    homeassistant --> piper
    homeassistant --> whisper

    %% Infrastructure Access
    code -.- ha_storage
    homeassistant -.- ha_storage
    homeassistant -.-> postgres
    piper -.- piper_storage
    whisper -.- whisper_storage

    %% Simple legend at bottom
    subgraph Legend[" "]
        direction LR
        hub[Hub Components]:::hub
        msg[Message Infrastructure]:::messaging
        ext[External Services]:::external
        inf[Infrastructure]:::infra
        dev[Development Tools]:::dev
        voi[Voice Components]:::voice
    end

    %% Styling
    class Legend legend
    class infrastructure legend
    class external legend
```

<!-- markdownlint-disable-next-line MD036 -->
<sup>*Line styles: Solid (→) = MQTT messaging, Dotted with dots (-.-) = Storage access, Dotted with arrow (-.→) = Database connections*</sup>

### Component Details

| Component | Type | Primary Role | Key Features | Integration Points |
| --- | --- | --- | --- | --- |
| Home Assistant | Core | Automation Platform | • Comprehensive device state management and tracking<br>• Advanced automation engine with scripting<br>• Modern web interface for configuration<br>• Persistent state in PostgreSQL database | • Bi-directional MQTT communication for devices<br>• State persistence through PostgreSQL<br>• Configuration management via Code Server<br>• Voice processing via Wyoming components |
| Code Server | Core | Configuration IDE | • Real-time YAML configuration editing<br>• Integrated syntax highlighting and validation<br>• Built-in version control capabilities<br>• Immediate config validation feedback | • Direct mount of Home Assistant configuration<br>• Secure internal-only access<br>• Efficient resource utilization |
| NanoMQ | Infrastructure | Message Broker | • Full MQTT v3.1.1/v5.0 protocol support<br>• Integrated WebSocket connectivity<br>• RESTful HTTP API interface<br>• Granular access control system | • Secure message routing between components<br>• Multi-protocol device communication<br>• Role-based authentication and ACL |
| Wyoming Piper | Voice | Text-to-Speech | • Local text-to-speech processing<br>• Multiple voice options<br>• Natural-sounding speech synthesis<br>• Low-latency response generation | • Direct integration with Home Assistant<br>• Voice response for automations<br>• Persistent model storage |
| Wyoming Whisper | Voice | Speech-to-Text | • Local speech recognition<br>• Accurate transcription capabilities<br>• Medium-sized language model<br>• Privacy-focused voice processing | • Direct integration with Home Assistant<br>• Voice command recognition<br>• Persistent model storage |
| Z-Wave JS UI | External | Device Integration | • Complete Z-Wave device management<br>• Real-time state publication<br>• Reliable command handling<br>• Network monitoring | • Secure MQTT communication as "zwavejs"<br>• Bi-directional state and command flow<br>• Integrated network management |
| Zigbee2MQTT | External | Device Integration | • Comprehensive Zigbee network management<br>• Automatic device discovery and pairing<br>• Sophisticated state control<br>• Device-specific configurations | • Secure MQTT communication as "zigbee2mqtt"<br>• Real-time device state updates<br>• Coordinated network control |
| BLE2MQTT | External | Device Integration | • Active Bluetooth device scanning<br>• Efficient state reporting system<br>• Reliable device control interface<br>• Connection management | • Secure MQTT communication as "ble2mqtt"<br>• Optimized state updates<br>• Managed device connections |

## Prerequisites

1. Required Flux Post-Build Variables

   The PostgreSQL cluster is always part of this module; its backups and its bootstrap-from-backup come from composing it with the [`db-backups`](../../../components/db-backups/README.md) and [`db-restore`](../../../components/db-restore/README.md) components. Those components reference several of the module's defaulted variables without a default of their own, so under strict post-build substitution a variable marked *required with `<component>`* must be supplied whenever that component is composed, even though the module alone would fall back to its default.

   | Name | Purpose | Used By |
   | --- | --- | --- |
   | domain_name | Hostname suffix for the Home Assistant ingresses and the NanoMQ service. Required | Home Assistant, NanoMQ |
   | secret_store | `ClusterSecretStore` the ExternalSecrets resolve against. Required | home-automation-secrets, db-backups |
   | db_name | PostgreSQL cluster name prefix. Defaults to `home-automation-db`; required with `db-backups` or `db-restore` | PostgreSQL, db-backups, db-restore |
   | db_suffix_current | PostgreSQL cluster name suffix (blue/green rotation), and the backup `serverName` it archives under. Defaults to `default`; required with `db-backups` | PostgreSQL, db-backups |
   | db_bootstrap_database | Initial database name created on bootstrap. Defaults to `home-assistant`; required with `db-restore` | PostgreSQL, db-restore |
   | db_bootstrap_owner | Initial database owner role created on bootstrap. Defaults to `home-assistant`; required with `db-restore` | PostgreSQL, db-restore |
   | db_replicas | PostgreSQL instance count. Defaults to `2` | PostgreSQL |
   | db_storage_size | PostgreSQL volume size. Required | PostgreSQL |
   | db_storage_class | PostgreSQL volume storage class. Required | PostgreSQL |
   | db_namespace | Namespace of the backup `ObjectStore`, credential and `ScheduledBackup`; must be this module's namespace. Required with `db-backups` | db-backups |
   | db_suffix_restore | `serverName` of the backup to bootstrap from. Required with `db-restore` | db-restore |
   | backup_s3_host | Host prefix of the backup object store; the endpoint is `https://<backup_s3_host>.<dns_zone>`. No default — required with `db-backups` | db-backups |
   | backup_s3_region | Region the backup store's requests are signed with. Defaults to `us-east-1` | db-backups |
   | backup_s3_accesskeyid_key | Secret-store item holding the backup store's access key ID. Defaults to `cluster_nas_minio_cloudnativepg_accesskeyid`; override together with `backup_s3_host` when changing stores | db-backups |
   | backup_s3_secretkey_key | Secret-store item holding the backup store's secret key. Defaults to `cluster_nas_minio_cloudnativepg_secretkey`; override together with `backup_s3_host` when changing stores | db-backups |
   | dns_zone | Domain the backup store endpoint is built under. Required with `db-backups` | db-backups |

2. Persistent Storage

   | PVC Name | Purpose | Access Mode |
   | --- | --- | --- |
   | home-assistant-data | Configuration and code-server data | RWX |
   | wyoming-piper-data | Text-to-speech model storage | RWO |
   | wyoming-whisper-data | Speech-to-text model storage | RWO |

3. Required Secrets

   | Secret Name | Purpose | Required Keys |
   | --- | --- | --- |
   | home-automation-secrets | Service configuration | homeassistant_secrets.yaml, nanomq_admin_password, nanomq_pwd.conf |

4. Required ConfigMaps

   | ConfigMap Name | Purpose | Required Keys |
   | --- | --- | --- |
   | nanomq-config | MQTT broker config | nanomq.conf, nanomq_acl.conf |

5. MQTT Authentication

   | Username | Purpose | Access |
   | --- | --- | --- |
   | homeassistant | Core platform | Allow |
   | zwavejs | Z-Wave integration | Allow |
   | zigbee2mqtt | Zigbee integration | Allow |
   | ble2mqtt | Bluetooth integration | Allow |
