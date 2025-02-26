#!/bin/bash
set -euo pipefail

RESOURCE_TYPE=""
RESOURCE_NAME=""
NAMESPACE="flux-system"
TIMEOUT="1m"

# Parse parameters
for param in "$@"
do
  case $param in
    --resource-type=*)
      RESOURCE_TYPE="${param#*=}"
      shift
      ;;
    --resource-name=*)
      RESOURCE_NAME="${param#*=}"
      shift
      ;;
    --namespace=*)
      NAMESPACE="${param#*=}"
      shift
      ;;
    --timeout=*)
      TIMEOUT="${param#*=}"
      shift
      ;;
    *)
      echo "Unknown parameter: $param"
      exit 1
      ;;
  esac
done

flux reconcile $RESOURCE_TYPE $RESOURCE_NAME -n $NAMESPACE --timeout $TIMEOUT
