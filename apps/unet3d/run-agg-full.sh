#!/bin/bash
#flux: --job-name=unet3d-dft-agg-full
#flux: -N 1
#flux: --queue=pdebug
#flux: --time-limit=10m
#flux: --setattr=system.exec.kill-timeout=120s

SOURCE_DIR=$(realpath $(dirname "${BASH_SOURCE[0]}"))

if [[ -z $ROOT_DIR ]]; then
    # Traverse up root dir until got _root_dir_
    ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "$ROOT_DIR" != "/" && ! -f "$ROOT_DIR/_root_dir_" ]]; do ROOT_DIR="$(dirname "$ROOT_DIR")"; done; [[ -f "$ROOT_DIR/_root_dir_" ]] || { echo "cannot find root dir of the project!"; exit 1; }
fi

# load necessary utilities
source $ROOT_DIR/scripts/utils.sh

NUM_NODES=32
EPOCHS=3
ID="unet3d"
TASK_NAME="dft-agg-full"
JOB_NAME="$ID-dft-agg-full"
DFTRACER_ENABLE_AGGREGATION=1
DFTRACER_AGGREGATION_TYPE=FULL

FLUX_LOG_DIR="$ROOT_DIR/flux_outputs/$ID/$TASK_NAME"
mkdir -p "$FLUX_LOG_DIR"
jobid=$(flux --parent batch -N $NUM_NODES \
  --exclusive \
  -o fastload=on \
  --time-limit=6h \
  --job-name="$JOB_NAME" \
  --env=ROOT_DIR="$ROOT_DIR" \
  --env=NUM_NODES="$NUM_NODES" \
  --env=EPOCHS="$EPOCHS" \
  --env=DFTRACER_ENABLE_AGGREGATION="$DFTRACER_ENABLE_AGGREGATION" \
  --env=DFTRACER_AGGREGATION_TYPE="$DFTRACER_AGGREGATION_TYPE" \
  --output="$FLUX_LOG_DIR/{{name}}-jobid_{{id}}-nodes_{{size}}.out" \
  $ROOT_DIR/apps/$ID/batch.sh)

log INFO "Queued experiment: \"$JOB_NAME\" and job ID: \"$jobid\""
