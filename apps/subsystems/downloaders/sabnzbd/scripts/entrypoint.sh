#!/bin/bash
set -e

echo Preparing...
if [[ ! -f /config/sabnzbd.ini ]]; then
  mkdir -p /config
  if [[ -f /sabnzbd.ini.preconfigured ]]; then
    echo "- Copying starter config file: /sabnzbd.ini.preconfigured -> /config/sabnzbd.ini..."
    cp /sabnzbd.ini.preconfigured /config/sabnzbd.ini
  fi
fi

echo Starting SABnzbd...
exec python3 /app/sabnzbd/SABnzbd.py --config-file /config/sabnzbd.ini --browser 0 --server 0.0.0.0
