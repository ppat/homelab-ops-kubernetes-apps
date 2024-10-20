#!/bin/bash
set -e

echo Preparing...
if [[ ! -f /config/config/config.yaml ]]; then
  mkdir -p /config/config
  if [[ -f /config.yaml.preconfigured ]]; then
    echo "- Copying starter config file: /config.yaml.preconfigured -> /config/config/config.yaml..."
    cp /config.yaml.preconfigured /config/config/config.yaml
  fi
fi

echo Starting Bazarr...
exec python3 -u /app/bazarr/bin/bazarr/main.py --no-update --config /config
