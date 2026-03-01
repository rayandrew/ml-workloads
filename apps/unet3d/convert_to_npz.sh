#!/bin/bash

DATASET_DIR="/p/lustre5/sinurat1/dataset/ml-workloads/unet3d-ori"
OUTPUT_DIR="/p/lustre5/sinurat1/dataset/ml-workloads/unet3d-npz"
PARALLEL_JOBS=64

mkdir -p "$OUTPUT_DIR"

echo "Counting source cases..."
mapfile -t source_files < <(find "$DATASET_DIR" -maxdepth 1 -name "case_*_x.npy")
NUM_SOURCES=${#source_files[@]}
echo "Found $NUM_SOURCES source .npy pairs"

convert_to_npz() {
    SRC_X="$1"
    OUTPUT_DIR="$2"
    SRC_Y="${SRC_X/_x.npy/_y.npy}"
    BASENAME_X="$(basename "${SRC_X%.npy}.npz")"
    BASENAME_Y="$(basename "${SRC_Y%.npy}.npz")"

    python3 -c "
import numpy as np
np.savez('$OUTPUT_DIR/$BASENAME_X', data=np.load('$SRC_X'))
np.savez('$OUTPUT_DIR/$BASENAME_Y', data=np.load('$SRC_Y'))
print(f'Converted -> $OUTPUT_DIR/$BASENAME_X, $OUTPUT_DIR/$BASENAME_Y')
"
}

export -f convert_to_npz

printf '%s\n' "${source_files[@]}" | parallel -j "$PARALLEL_JOBS" convert_to_npz {} "$OUTPUT_DIR"

echo "Done! Converted $NUM_SOURCES cases to $OUTPUT_DIR"