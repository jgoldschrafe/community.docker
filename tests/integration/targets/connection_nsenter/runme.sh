#!/usr/bin/env bash

set -euo pipefail

[[ -n "${DEBUG:-}" || -n "${ANSIBLE_DEBUG:-}" ]] && set -x

readonly IMAGE="quay.io/ansible/toolset:latest"
readonly COLLECTION_ROOT="$(cd ../../../.. ; pwd)"
readonly COLLECTIONS_PATH="$(cd ../../../../../../.. ; pwd)"
readonly PYTHON="$(command -v python3 python | head -n1)"

# Setup phase
echo "Setup"
ANSIBLE_ROLES_PATH=.. ansible-playbook setup.yml

# If docker wasn't installed, don't run the tests
if [ "$(command -v docker)" == "" ]; then
    exit
fi

cleanup() {
    echo "Cleanup"
    echo "Shutdown"
    ANSIBLE_ROLES_PATH=.. ansible-playbook shutdown.yml
    echo "Done"
    exit 0
}

envs=(--env "HOME=${HOME:-}")
while IFS=$'\0' read -d '' -r line; do
    key="$(echo "$line" | cut -d= -f1)"
    value="$(echo "$line" | cut -d= -f2-)"
    if [[ "${key}" =~ ^(ANSIBLE_|JUNIT_OUTPUT_DIR$|OUTPUT_DIR$|PYTHONPATH$) ]]; then
        envs+=(--env "${key}=${value}")
    fi
done < <(printenv -0)

# Make sure the directory containing ansible_collections is in Ansible's search path
if [ "${ANSIBLE_COLLECTIONS_PATHS}" == "" ]; then
    envs+=(--env "ANSIBLE_COLLECTIONS_PATHS=${COLLECTIONS_PATH}")
else
    envs+=(--env "ANSIBLE_COLLECTIONS_PATHS=${COLLECTIONS_PATH}:${ANSIBLE_COLLECTIONS_PATHS}")
fi

# Test phase
cat > test_connection.inventory << EOF
[nsenter]
nsenter-no-pipelining ansible_pipelining=false
nsenter-pipelining    ansible_pipelining=true

[nsenter:vars]
ansible_host=localhost
ansible_connection=community.docker.nsenter
ansible_host_volume_mount=/host
ansible_nsenter_pid=1
ansible_python_interpreter=${PYTHON}
EOF

echo "Run tests"
docker run \
    -it \
    --rm \
    --privileged \
    --pid host \
    "${envs[@]}" \
    --volume "${COLLECTION_ROOT}:${COLLECTION_ROOT}" \
    --workdir "$(pwd)" \
    "${IMAGE}" \
    ./runme-connection.sh "$@"
