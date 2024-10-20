#!/bin/sh
set -e

echo Preparing...
if [ ! -f /app/config/settings.json ]; then
  mkdir -p /app/config
  if [ -f /settings.json.preconfigured ]; then
    echo "- Copying starter config file: /settings.json.preconfigured -> /app/config/settings.json..."
    cp /settings.json.preconfigured /app/config/settings.json
  fi
fi

echo Starting...
cd /app
exec /sbin/tini -- yarn start
