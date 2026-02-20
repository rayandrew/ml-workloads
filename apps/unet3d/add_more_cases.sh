#!/bin/bash

# Note:
# Since unet3d is small, this script is needed for I/O performance testing.
# It will create new cases by linking to existing cases.
# Please make sure the source cases are properly prepared before running this script.

DATASET_DIR="/p/lustre5/sinurat1/dataset/ml-workloads/unet3d"
PARALLEL_JOBS=64

echo "Counting source cases..."
# mapfile -t source_files < <(ls "$DATASET_DIR"/case_*_x.npy)
# NUM_SOURCES=${#source_files[@]}
mapfile -t source_files < <(find "$DATASET_DIR" -maxdepth 1 -name "case_*_x.npy")
NUM_SOURCES=${#source_files[@]}
echo "Found $NUM_SOURCES source cases"
START_CASE=$NUM_SOURCES

read -p "How many total cases do you want? (current: $NUM_SOURCES, enter target): " TOTAL_CASES

# Pre-generate work list once in main shell
WORK_FILE=$(mktemp)
for i in $(seq $START_CASE $(( TOTAL_CASES - 1 ))); do
    RAND_IDX=$(( RANDOM % NUM_SOURCES ))
    echo "$i ${source_files[$RAND_IDX]}"
done > "$WORK_FILE"
echo "Work list generated ($(wc -l < $WORK_FILE) jobs), linking..."

create_link() {
    TARGET_CASE="$1"
    SRC_X="$2"
    DATASET_DIR="$3"
    SRC_Y="${SRC_X/_x.npy/_y.npy}"

    DEST_X="$DATASET_DIR/case_$(printf '%05d' $TARGET_CASE)_x.npy"
    DEST_Y="$DATASET_DIR/case_$(printf '%05d' $TARGET_CASE)_y.npy"

    ln "$SRC_X" "$DEST_X"
    ln "$SRC_Y" "$DEST_Y"
    echo "Created case $(printf '%05d' $TARGET_CASE)"
}

export -f create_link

parallel -j $PARALLEL_JOBS --colsep ' ' create_link {1} {2} "$DATASET_DIR" :::: "$WORK_FILE"

rm "$WORK_FILE"
echo "Done! Created $(( TOTAL_CASES - START_CASE )) new cases."