#!/bin/bash

# set -ex

if [[ -z $ROOT_DIR ]]; then
    # Traverse up root dir until got _root_dir_
    ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "$ROOT_DIR" != "/" && ! -f "$ROOT_DIR/_root_dir_" ]]; do ROOT_DIR="$(dirname "$ROOT_DIR")"; done
    [[ -f "$ROOT_DIR/_root_dir_" ]] || { echo "cannot find root dir of the project!"; exit 1; }
fi

# load necessary utilities
source $ROOT_DIR/scripts/utils.sh

cluster=$(get_cluster_name)
# =========================
# Arguments
# =========================
ENV_DIR="$ROOT_DIR/.venvs/$cluster"
NO_PYTHON=0

usage() {
    echo "Usage: $0 --env-dir <path> [--no-python]"
    echo "    --env-dir (default: $ROOT_DIR/.env)"
    echo "    --no-python (default: false)"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --env-dir)
            ENV_DIR="$2"
            shift 2
            ;;
        --no-python)
            NO_PYTHON=1
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validation of arguments
## making sure env_dir is defined properly
[[ -z "$ENV_DIR" ]] && log ERROR "Error: --env-dir are required." && echo && usage
# =========================

# env: load specific platform configuration
if [[ $cluster == "corona" ]]; then
    source $ROOT_DIR/scripts/platforms/corona/env.sh
elif [[ $cluster == "tuolumne" ]]; then
    source $ROOT_DIR/scripts/platforms/tuolumne/env.sh
fi

# env: prelude
# place where we load necessary modules for specific platform
env_prelude

if [[ $NO_PYTHON -eq 0 ]]; then
    # cache folder
    pkgdir=$ROOT_DIR/.cache/pip
    mkdir -p $pkgdir
    export PIP_CACHE_DIR=$pkgdir

    # re-exporting venv dir
    export VENV_DIR="$ENV_DIR"
    env_create_venv
    source $VENV_DIR/bin/activate

    log "Python version: $(python --version)"

    # Default packages
    need_python_pkg pkg=psutil
    need_python_pkg pkg=strenum

    export PYTHONPATH="$ROOT_DIR:$PYTHONPATH"
fi
