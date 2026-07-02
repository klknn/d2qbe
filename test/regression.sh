#!/bin/bash
set -e

ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "amd64" ]; then
  echo "Skipping test-regression: dqbe only supports x86_64 architecture (host is $ARCH)"
  exit 0
fi

./dqbe < test/liveness_bug.ssa > tmp_liveness_bug.s
cc -o tmp_liveness_bug tmp_liveness_bug.s
./tmp_liveness_bug
rm -f tmp_liveness_bug.s tmp_liveness_bug
