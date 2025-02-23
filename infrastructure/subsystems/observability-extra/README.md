# Observability Extra

This module extends the core observability stack with specialized collectors and exporters for comprehensive system monitoring.

## Quick Links

- [Kubernetes Event Exporter Documentation](https://github.com/opsgenie/kubernetes-event-exporter)
- [Node Problem Detector Documentation](https://github.com/kubernetes/node-problem-detector)
- [SNMP Exporter Documentation](https://github.com/prometheus/snmp_exporter)
- [Syslog-ng Documentation](https://www.syslog-ng.com/technical-documents/doc/syslog-ng-open-source-edition/3.37/administration-guide/)
- [UniFi Poller Documentation](https://unpoller.com/)

## Overview

The observability-extra module provides five main capabilities:

1. Event Collection
   - Kubernetes event export to Loki:
     - 60-second event retention
     - Custom stream labels
     - Flexible routing rules
     - Structured logging
   - Node problem detection:
     - System log monitoring
     - Kernel problem detection
     - Custom problem definitions
     - Prometheus alerts

2. Network Monitoring
   - SNMP metrics collection:
     - Custom scrape configurations
     - Instance relabeling
     - Anti-affinity rules
     - Timeout handling
   - UniFi statistics:
     - Site metrics
     - Device status
     - Network utilization
     - Secure credential handling

3. Log Aggregation
   - Syslog collection:
     - RFC3164 support (UDP/514)
     - RFC5424 support (TCP/601)
     - UTF-8 sanitization
     - Flow control
   - Performance features:
     - Connection pooling
     - Batch processing
     - Worker scaling
     - Buffer tuning

### Component Architecture

```mermaid
flowchart TB
    %% Color scheme
    classDef event fill:#a7f3d0,stroke:#059669,color:#064e3b
    classDef network fill:#bfdbfe,stroke:#3b82f6,color:#1e3a8a
    classDef log fill:#fecaca,stroke:#dc2626,color:#7f1d1d
    classDef storage fill:#fde68a,stroke:#d97706,color:#92400e
    classDef infra fill:#e5e7eb,stroke:#6b7280,color:#374151
    classDef legend fill:none,stroke:none,color:#6b7280

    %% Event Sources
    subgraph events["Event Collection"]
        direction TB
        k8s-events["Kubernetes Events"]:::event
        node-problems["Node Problems"]:::event
        event-exporter["Event Exporter"]:::event
        problem-detector["Problem Detector"]:::event
    end

    %% Network Sources
    subgraph network["Network Monitoring"]
        direction TB
        snmp-devices["SNMP Devices"]:::network
        unifi-devices["UniFi Devices"]:::network
        snmp-exporter["SNMP Exporter"]:::network
        unpoller["UniFi Poller"]:::network
    end

    %% Log Sources
    subgraph logs["Log Collection"]
        direction TB
        rfc3164["Syslog UDP/514<br/>RFC3164"]:::log
        rfc5424["Syslog TCP/601<br/>RFC5424"]:::log
        syslog-ng["Syslog-ng<br/>Aggregator"]:::log
    end

    %% Storage
    subgraph storage["Storage Layer"]
        direction TB
        loki["Loki<br/>Log Storage"]:::storage
        prometheus["Prometheus<br/>Metrics Storage"]:::storage
    end

    %% Event Flow
    k8s-events --> event-exporter
    node-problems --> problem-detector
    event-exporter --> loki
    problem-detector --> prometheus

    %% Network Flow
    snmp-devices --> snmp-exporter
    unifi-devices --> unpoller
    snmp-exporter --> prometheus
    unpoller --> prometheus

    %% Log Flow
    rfc3164 --> syslog-ng
    rfc5424 --> syslog-ng
    syslog-ng --> loki

    %% Legend
    subgraph Legend[" "]
        direction LR
        event-l["Events"]:::event
        network-l["Network"]:::network
        log-l["Logs"]:::log
        storage-l["Storage"]:::storage
        style Legend fill:none,stroke:none
    end
```

### Component Details

| Component | Primary Role | Integration Points |
|-----------|-------------|-------------------|
| Event Exporter | Event collection | • Exports Kubernetes events<br>• Routes to Loki<br>• Custom stream labels<br>• 60s event retention |
| Problem Detector | Node monitoring | • System log analysis<br>• Kernel monitoring<br>• PrometheusRules<br>• ServiceMonitor enabled |
| SNMP Exporter | Network metrics | • Custom scrape configs<br>• Instance relabeling<br>• Anti-affinity rules<br>• Timeout handling |
| Syslog-ng | Log aggregation | • Dual protocol support<br>• Batch processing<br>• Worker scaling<br>• Flow control |
| UniFi Poller | Network stats | • Site monitoring<br>• Device metrics<br>• Secure credentials<br>• Prometheus integration |

## Prerequisites

1. Required Components

   | Component | Purpose | Configuration |
   |-----------|---------|---------------|
   | Loki | Log storage | From observability-core |
   | Prometheus | Metrics storage | From observability-core |
   | UniFi Controller | Network stats | From networking-extra |

2. Required Variables

   | Variable | Purpose | Example |
   |----------|---------|---------|
   | domain_name | UniFi URL | example.com |

3. Required Secrets

   | Secret Name | Purpose | Required Keys |
   |-------------|---------|---------------|
   | unpoller-credentials | UniFi access | unpoller_username, unpoller_password |

## Dependencies

### Required By

- Application modules requiring:
  - Event monitoring
  - Network metrics
  - Log aggregation
  - Problem detection

### Depends On

- [observability-core](../observability-core) - For storage backends
- [networking-extra](../networking-extra) - For UniFi integration

## Usage

### Event Collection

```yaml
# Example: Configure event export to Loki
apiVersion: v1
kind: ConfigMap
metadata:
  name: event-exporter-config
  namespace: logging
data:
  config.yaml: |
    logLevel: info
    maxEventAgeSeconds: 60
    receivers:
      - name: loki
        loki:
          url: http://loki-write:3100/loki/api/v1/push
          streamLabels:
            job: event-exporter
            stream: event
```

### Network Monitoring

```yaml
# Example: Configure SNMP target
apiVersion: v1
kind: ConfigMap
metadata:
  name: snmp-exporter-config
  namespace: monitoring
data:
  snmp.yaml: |
    modules:
      router:
        walk:
          - 1.3.6.1.2.1.2.2  # Interfaces
          - 1.3.6.1.2.1.31.1 # IF-MIB
        metrics:
          - name: ifOperStatus
            oid: 1.3.6.1.2.1.2.2.1.8
            type: gauge
```

### Log Collection

```yaml
# Example: Configure syslog input
source s_network {
  network(
    ip("0.0.0.0")
    port(514)
    transport("udp")
    flags(sanitize-utf8)
  );
};

destination d_loki {
  loki(
    url("http://loki:3100")
    labels(
      "job" => "syslog"
      "host" => "$HOST"
    )
  );
};
```
