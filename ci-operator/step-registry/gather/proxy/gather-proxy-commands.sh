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
if [ -f "${SHARED_DIR}/proxyip" ]; then
  proxy_ip="$(cat ${SHARED_DIR}/proxyip)"
  proxy_dir="${ARTIFACT_DIR}/proxy"
  mkdir -p ${proxy_dir}

  if ! whoami &> /dev/null; then
    if [ -w /etc/passwd ]; then
      echo "${USER_NAME:-default}:x:$(id -u):0:${USER_NAME:-default} user:${HOME}:/sbin/nologin" >> /etc/passwd
    fi
  fi
  eval "$(ssh-agent)"
  ssh-add /etc/openshift-installer/ssh-privatekey
  ssh -A -o PreferredAuthentications=publickey -o StrictHostKeyChecking=false -o UserKnownHostsFile=/dev/null core@${proxy_ip} 'journalctl -u squid' > ${proxy_dir}/squid.service
fi