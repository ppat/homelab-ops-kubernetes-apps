# Misc Subsystem

Collection of miscellaneous applications that provide specialized functionality without requiring dedicated modules.

## Quick Links

<a href="https://github.com/foxcpp/maddy" target="_blank">Maddy</a>

## Overview

The misc subsystem serves as a home for smaller, focused applications that provide specific utility functions. Unlike other modules that group related applications or contain complex systems requiring dedicated modules, this module houses lightweight applications that deliver targeted functionality.

The misc subsystem currently consists of three main capability groups:

1. Email Relay
   - SMTP server with TLS support
   - Email relaying to external SMTP provider
   - Local authentication

### Component Details

| Component | Type | Primary Role | Key Features | Integration Points |
|-----------|------|--------------|--------------|-------------------|
| Maddy | Core | SMTP Server | • Email relay with TLS support<br>• Authentication handling | • External SMTP providers<br>• Local authentication |

## Prerequisites

1. Required Secrets

   | Secret Name | Purpose | Required Keys |
   |-------------|---------|---------------|
   | maddy-credentials | SMTP authentication | smtp_remote_user, smtp_remote_password, smtp_remote_host, smtp_remote_port, smtp_local_auth |

2. Required Variables

   | Variable | Purpose | Used By |
   |----------|---------|---------|
   | domain_name | External access URL (smtp.${domain_name}) | Maddy |
   | cert_issuer | Certificate issuer reference | Certificate |
   | secret_store | External secret store reference | ExternalSecret |
