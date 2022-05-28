#!/bin/bash

# Test that a provisioned instance is set up properly and meets requirements
#   ./test.sh BINDINGINFO.json
#
# Returns 0 (if all tests PASS)
#      or 1 (if any test FAILs).

set -e
retval=0

if [[ -z ${1+x} ]] ; then
    echo "Usage: ./test.sh BINDINGINFO.json"
    exit 1
fi

SERVICE_INFO="$(jq -r .credentials < "$1")"

echo "Running tests..."
