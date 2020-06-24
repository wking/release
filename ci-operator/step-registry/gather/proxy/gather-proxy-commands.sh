#!/bin/bash
set -o nounset
set -o errexit
set -o pipefail

trap 'CHILDREN=$(jobs -p); if test -n "${CHILDREN}"; then kill ${CHILDREN} && wait; fi' TERM

STACK_NAME="${NAMESPACE}-${JOB_NAME_HASH}-proxy"

aws cloudformation delete-stack --stack-name "${STACK_NAME}" &
wait "$!"

aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}" &
wait "$!"

# collect logs from the proxy here