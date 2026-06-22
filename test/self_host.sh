#!/bin/bash
set -e

echo "Compiling source/d2qbe/app.d using bootstrap compiler..."
./d2qbe source/d2qbe/app.d > test/self_host.s

echo "Assembling self_host.s..."
./qbe/qbe < test/self_host.s > test/self_host_qbe.s
cc -o test/d2qbe_self_hosted test/self_host_qbe.s ext.o

echo "Running tests using self-hosted compiler..."
D2QBE=./test/d2qbe_self_hosted ./test/run.sh

echo "Self-hosting test PASSED!"
