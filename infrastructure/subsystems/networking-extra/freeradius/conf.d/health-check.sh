#!/bin/sh

# FreeRADIUS Health Check Script
# Tests if the FreeRADIUS server is properly responding to auth requests

# Make sure we have the secrets we need
if [ -z "$HEALTHCHECK_PASSWORD" ]; then
  echo "HEALTHCHECK_PASSWORD environment variable not set"
  exit 1
fi
if [ -z "$HEALTHCHECK_SECRET" ]; then
  echo "HEALTHCHECK_SECRET environment variable not set"
  exit 1
fi

# Run the healthcheck test
NAS_PORT="0"
result=$(radtest -P udp "healthcheck" "$HEALTHCHECK_PASSWORD" "127.0.0.1:1812" "$NAS_PORT" "$HEALTHCHECK_SECRET" 2>&1)

# Check for connection failure (RADIUS server not running)
if echo "$result" | grep -q "No reply"; then
  echo "FreeRADIUS server is not responding"
  exit 1
fi

# Check for server response (even a rejection means the server is running)
if echo "$result" | grep -q "Received Access-"; then
  echo "FreeRADIUS server is responding to authentication requests"
  exit 0
else
  echo "Unexpected response from FreeRADIUS server"
  echo "$result"
  exit 1
fi
