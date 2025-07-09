#!/bin/sh
set -e

KEEP_COUNT=${LOG_ROTATION_KEEP_COUNT:-5}
FULL_LOG_PATH="${LOG_PATH}/${LOG_FILE_NAME}"

echo "Log rotator started. Watching ${FULL_LOG_PATH}. Will keep ${KEEP_COUNT} rotated logs."

while true; do
  # Only run the rotation logic if the main log file exists and is not empty
  if [ -s "${FULL_LOG_PATH}" ]; then
    echo "Running rotation for ${FULL_LOG_PATH}..."

    # 1. Delete the oldest log file to make space.
    rm -f "${FULL_LOG_PATH}.${KEEP_COUNT}"

    # 2. Shift all old logs up by one, starting from the second oldest.
    #    This loop runs from N-1 down to 1. E.g., for N=5, it runs for 4, 3, 2, 1.
    #    This renames access.log.4 to access.log.5, then .3 to .4, etc.
    i=$((KEEP_COUNT-1))
    while [ ${i} -ge 1 ]; do
      if [ -f "${FULL_LOG_PATH}.${i}" ]; then
        echo "  - Shifting ${FULL_LOG_PATH}.${i} to ${FULL_LOG_PATH}.$((i+1))"
        mv "${FULL_LOG_PATH}.${i}" "${FULL_LOG_PATH}.$((i+1))"
      fi
      i=$((i-1))
    done

    # 3. Copy the current active log file to the .1 position.
    echo "  - Copying active log to ${FULL_LOG_PATH}.1"
    cp "${FULL_LOG_PATH}" "${FULL_LOG_PATH}.1"

    # 4. Truncate the active log file, preserving the file handle (inode).
    #    This is the most critical step for seamless log ingestion.
    echo "  - Truncating active log file ${FULL_LOG_PATH}"
    cat /dev/null > "${FULL_LOG_PATH}"

    echo "Rotation complete."
  else
    echo "Log file ${FULL_LOG_PATH} is empty or does not exist. Skipping rotation."
  fi

  echo "Sleeping for 4 hours..."
  sleep 14400
  echo
done
