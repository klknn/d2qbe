#!/bin/bash
set -e

# Resolve the absolute path to filter_msg.py relative to this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
FILTER_PY="${DIR}/filter_msg.py"

if [ ! -f "$FILTER_PY" ]; then
  echo "Error: ${FILTER_PY} not found." >&2
  exit 1
fi

RANGE="$*"
if [ -z "$RANGE" ]; then
  # Default to origin/main..HEAD if no range is specified
  RANGE="origin/main..HEAD"
fi

echo "Rewriting commit messages in range: ${RANGE}"
git filter-branch --force --msg-filter "python3 ${FILTER_PY}" ${RANGE}
