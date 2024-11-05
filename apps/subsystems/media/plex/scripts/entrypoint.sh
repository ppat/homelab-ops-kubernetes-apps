#!/bin/bash
set -eo pipefail

####################################################################################################################
# Custom entrypoint lets us avoid having to run the container as root. The builtin entrypoint uses a s6-init
# that requires elevated capabilities. Using this custom entrypoint allows us to avoid that by instead using
# kubernetes security context features to provides the necessary file ownership permissions.
####################################################################################################################
PLEX_HOME="/config"
PLEX_MEDIA_SERVER_DIR="${PLEX_HOME}/Library/Application Support/Plex Media Server"
PLEX_PREF_FILE="${PLEX_MEDIA_SERVER_DIR}/Preferences.xml"

echo "Preparing directories for Plex Media Server..."
if [[ ! -d "${PLEX_MEDIA_SERVER_DIR}" ]]; then
  echo "- Plex Media Server directory does not exist... creating."
  mkdir -p "${PLEX_MEDIA_SERVER_DIR}"
fi
echo "- Symlinking /var/log/plex -> ${PLEX_MEDIA_SERVER_DIR}/Logs..."
ln -sf /var/log/plex "${PLEX_MEDIA_SERVER_DIR}/Logs"
echo
if [[ -f "${PLEX_MEDIA_SERVER_DIR}/plexmediaserver.pid" ]]; then
  echo "- Cleaning up PID file from a previous run..."
  rm "${PLEX_MEDIA_SERVER_DIR}/plexmediaserver.pid"
fi

echo "Updating Plex Media Server preferences file..."
if [[ ! -e "${PLEX_PREF_FILE}" ]]; then
  echo "- Creating preferences stub..."
  cat > "${PLEX_PREF_FILE}" <<-EOF
<?xml version="1.0" encoding="utf-8"?>
<Preferences/>
EOF
fi

####################################################################################################################
# This initializes the plex preferences file if it doesn't already exist.
#
# Based on https://github.com/plexinc/pms-docker/blob/master/root/etc/cont-init.d/40-plex-first-run.
####################################################################################################################
function getPref {
  local key="$1"

  xmlstarlet sel -T -t -m "/Preferences" -v "@${key}" -n "${PLEX_PREF_FILE}"
}

function setPref {
  local key="$1"
  local value="$2"
  echo "- Updating preference: $key..."
  count="$(xmlstarlet sel -t -v "count(/Preferences/@${key})" "${PLEX_PREF_FILE}")"
  count=$((count + 0))
  if [[ $count -gt 0 ]]; then
    xmlstarlet ed --inplace --update "/Preferences/@${key}" -v "${value}" "${PLEX_PREF_FILE}"
  else
    xmlstarlet ed --inplace --insert "/Preferences"  --type attr -n "${key}" -v "${value}" "${PLEX_PREF_FILE}"
  fi
}

# Setup Server's client identifier
serial="$(getPref "MachineIdentifier")"
if [ -z "${serial}" ]; then
  serial="$(uuidgen)"
  setPref "MachineIdentifier" "${serial}"
fi
clientId="$(getPref "ProcessedMachineIdentifier")"
if [ -z "${clientId}" ]; then
  clientId="$(echo -n "${serial}- Plex Media Server" | sha1sum | cut -b 1-40)"
  setPref "ProcessedMachineIdentifier" "${clientId}"
fi

# Get server token and only turn claim token into server token if we have former but not latter.
token="$(getPref "PlexOnlineToken")"
if [ ! -z "${PLEX_CLAIM}" ] && [ -z "${token}" ]; then
  echo "Attempting to obtain server token from claim token"
  loginInfo="$(curl -X POST \
        -H 'X-Plex-Client-Identifier: '${clientId} \
        -H 'X-Plex-Product: Plex Media Server'\
        -H 'X-Plex-Version: 1.1' \
        -H 'X-Plex-Provides: server' \
        -H 'X-Plex-Platform: Linux' \
        -H 'X-Plex-Platform-Version: 1.0' \
        -H 'X-Plex-Device-Name: PlexMediaServer' \
        -H 'X-Plex-Device: Linux' \
        "https://plex.tv/api/claim/exchange?token=${PLEX_CLAIM}")"
  token="$(echo "$loginInfo" | sed -n 's/.*<authentication-token>\(.*\)<\/authentication-token>.*/\1/p')"

  if [ "$token" ]; then
    echo "Token obtained successfully"
    setPref "PlexOnlineToken" "${token}"
  fi
fi

if [ ! -z "${ADVERTISE_IP}" ]; then
  setPref "customConnections" "${ADVERTISE_IP}"
fi

if [ ! -z "${ALLOWED_NETWORKS}" ]; then
  setPref "allowedNetworks" "${ALLOWED_NETWORKS}"
fi

# Set transcoder temp if not yet set
if [ -z "$(getPref "TranscoderTempDirectory")" ]; then
  setPref "TranscoderTempDirectory" "/transcode"
fi


####################################################################################################################
# Enables us to provide additional configuration parameters for Preferences.xml as environment variables.
#
# Based on https://github.com/onedr0p/containers/blob/main/apps/plex/entrypoint.sh#L97.
####################################################################################################################
# Parse list of all exported variables that start with PLEX_PREFERENCE_
# The format of which is PLEX_PREFERENCE_<SOMETHING>="Key=Value"
# Where Key is the EXACT key to use in the Plex Preference file
# And Value is the EXACT value to use in the Plex Preference file for that key.
# Please note it looks like many of the key's are camelCase in some fashion.
# Additionally there are likely some preferences where environment variable injection
# doesn't really work for.
for var in "${!PLEX_PREFERENCE_@}"; do
    value="${!var}"
    PreferenceValue="${value#*=}"
    PreferenceKey="${value%=*}"
    setPref "${PreferenceKey}" "${PreferenceValue}"
done

echo "Plex Media Server preferences updated."
echo


####################################################################################################################
# Start plex server.
#
# Based on https://github.com/plexinc/pms-docker/blob/master/root/etc/services.d/plex/run
####################################################################################################################
echo "Starting Plex Media Server."
export PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR="${PLEX_HOME}/Library/Application Support"
export PLEX_MEDIA_SERVER_HOME="/usr/lib/plexmediaserver"
export PLEX_MEDIA_SERVER_MAX_PLUGIN_PROCS=6
export PLEX_MEDIA_SERVER_INFO_VENDOR="Docker"
export PLEX_MEDIA_SERVER_INFO_DEVICE="Docker Container"
export PLEX_MEDIA_SERVER_INFO_MODEL="$(uname -m)"
export PLEX_MEDIA_SERVER_INFO_PLATFORM_VERSION="$(uname -r)"
exec /usr/lib/plexmediaserver/Plex\ Media\ Server
