# AI Subsystem

Self-hosted AI platform providing local large language model capabilities and a web interface for interacting with AI models.

## Quick Links

- [Ollama Documentation](https://github.com/ollama/ollama)
- [Ollama GitHub Repository](https://github.com/ollama/ollama)
- [OpenWebUI Documentation](https://docs.openwebui.com/)
- [OpenWebUI GitHub Repository](https://github.com/open-webui/open-webui)

## Overview

The AI subsystem consists of two main capability groups:

1. AI Model Serving
   - Local large language model hosting
   - Model management and versioning
   - API-based model interaction
   - Efficient resource utilization

2. User Interface
   - Web-based chat interface
   - Model selection and configuration
   - Conversation history management
   - Optional external LLM integration

## Component Architecture

The following diagram illustrates how the AI subsystem components work together, showing the relationship between the LLM server, web interface, and how users interact with the system.

```mermaid
flowchart TB
    %% Color scheme with good contrast for light/dark themes
    classDef core fill:#a7f3d0,stroke:#059669,color:#064e3b
    classDef ui fill:#bfdbfe,stroke:#3b82f6,color:#1e3a8a
    classDef storage fill:#d8b4fe,stroke:#9333ea,color:#581c87
    classDef external fill:#fde68a,stroke:#d97706,color:#92400e
    classDef legend fill:none,stroke:none,color:#6b7280

    %% External Access
    user[User]:::external
    cloud[Cloud LLMs]:::external

    %% Core Components - Module Provided
    subgraph module[AI Module]
        ollama[Ollama LLM Server]:::core
        openwebui[OpenWebUI Interface]:::ui
    end

    %% Storage Components - Dependencies
    subgraph storage[Storage Dependencies]
        ollama_pvc[(PVC: ollama)]:::storage
        openwebui_pvc[(PVC: openwebui)]:::storage
    end

    %% Relationships
    user --> ollama
    user --> openwebui

    openwebui --> ollama
    openwebui -.-> cloud

    ollama --> ollama_pvc
    openwebui --> openwebui_pvc
```

<sup>*Line styles: Solid (→) = Direct interaction, Dotted (-.→) = Optional connection*</sup>

### Component Details

| Component | Type | Primary Role | Key Features | Integration Points |
|-----------|------|--------------|--------------|-------------------|
| Ollama | Core | LLM Server | • Run large language models locally<br>• Efficient model management<br>• API-based interaction<br>• Model downloading and serving | • Direct user access via API<br>• OpenWebUI integration<br>• Persistent storage for models |
| OpenWebUI | Core | Web Interface | • User-friendly chat interface<br>• Conversation management<br>• Model selection and configuration<br>• Optional cloud LLM integration | • Ollama API integration<br>• Direct user access via web browser<br>• Persistent storage for settings |

## Prerequisites

1. Persistent Storage

   | PVC Name | Purpose | Access Mode |
   |----------|---------|-------------|
   | ollama | Model storage and configuration | RWX |
   | openwebui | User settings and conversation history | RWX |

2. Required Variables

   | Variable | Purpose | Used By |
   |----------|---------|---------|
   | domain_name | External access URL (ollama.${domain_name}, openwebui.${domain_name}) | Ollama, OpenWebUI |
