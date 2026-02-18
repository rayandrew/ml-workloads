#!/bin/bash

SOURCE_DIR=$(realpath $(dirname "${BASH_SOURCE[0]}"))

if [[ -z $ROOT_DIR ]]; then
    # Traverse up root dir until got _root_dir_
    ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "$ROOT_DIR" != "/" && ! -f "$ROOT_DIR/_root_dir_" ]]; do ROOT_DIR="$(dirname "$ROOT_DIR")"; done; [[ -f "$ROOT_DIR/_root_dir_" ]] || { echo "cannot find root dir of the project!"; exit 1; }
fi

TEMP_DIR=$(mktemp -d)

cleanup() {
    echo "Cleaning up resources..."
    rm -rf $TEMP_DIR
}

trap cleanup EXIT


# =========================
# Arguments
# =========================
DATA_DIR=""
OUTPUT_DIR=""
VERIFY=0

usage() {
    echo "Usage: $0 --input <path> --output <path>"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)
            DATA_DIR="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --verify)
            VERIFY=1
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
[[ -z "$DATA_DIR" || -z "$OUTPUT_DIR" ]] && log ERROR "Error: --input and --output are required." && echo && usage
# =========================

# setup environment
source $ROOT_DIR/scripts/setup-env.sh --env-dir $TEMP_DIR/env

need_pytorch

pip install -r $SOURCE_DIR/requirements.txt

log "Preprocessing data"
python $SOURCE_DIR/preprocess-dataset.py --data_dir $DATA_DIR --results_dir $OUTPUT_DIR --mode preprocess

if is_truthy "$NO_VERIFY"; then
    log "Verifying data"
    python $SOURCE_DIR/preprocess-dataset.py --data_dir $DATA_DIR --results_dir $OUTPUT_DIR --mode verify
fi