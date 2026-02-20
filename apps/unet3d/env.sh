#!/bin/bash

SOURCE_DIR=$(realpath $(dirname "${BASH_SOURCE[0]}"))

if [[ -z $ROOT_DIR ]]; then
    # Traverse up root dir until got _root_dir_
    ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "$ROOT_DIR" != "/" && ! -f "$ROOT_DIR/_root_dir_" ]]; do ROOT_DIR="$(dirname "$ROOT_DIR")"; done; [[ -f "$ROOT_DIR/_root_dir_" ]] || { echo "cannot find root dir of the project!"; exit 1; }
fi

# load necessary utilities
source $ROOT_DIR/scripts/utils.sh

cleanup() {
    echo ""
}

trap cleanup EXIT

CLUSTER=$(get_cluster_name)
LUSTRE_USER_LOC=$(get_lustre_user_loc)

# setup environment
source $ROOT_DIR/scripts/setup-env.sh --env-dir $LUSTRE_USER_LOC/venvs/ml-workloads/$CLUSTER/unet3d

DEVELOPMENT=1

need_pytorch
need_mpi4py
need_dllogger
need_dftracer dev=$DEVELOPMENT
need_dftracer_utils
need_python_pkg pkg="numba"
need_python_pkg pkg="tqdm"