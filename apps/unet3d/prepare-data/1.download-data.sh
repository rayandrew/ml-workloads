#!/bin/bash

SOURCE_DIR=$(realpath $(dirname "${BASH_SOURCE[0]}"))

if [[ -z $ROOT_DIR ]]; then
    # Traverse up root dir until got _root_dir_
    ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "$ROOT_DIR" != "/" && ! -f "$ROOT_DIR/_root_dir_" ]]; do ROOT_DIR="$(dirname "$ROOT_DIR")"; done; [[ -f "$ROOT_DIR/_root_dir_" ]] || { echo "cannot find root dir of the project!"; exit 1; }
fi

# load necessary utilities
source $ROOT_DIR/scripts/utils.sh

TEMP_DIR=$(mktemp -d)

cleanup() {
    echo "Cleaning up resources..."
    rm -rf $TEMP_DIR
}

trap cleanup EXIT

# setup environment
source $ROOT_DIR/scripts/setup-env.sh --env-dir $TEMP_DIR/env

mkdir raw-data-dir
cd raw-data-dir
git clone https://github.com/neheller/kits19
cd kits19
pip3 install -r requirements.txt
python3 -m starter_code.get_imaging