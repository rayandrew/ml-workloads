#!/bin/bash
#flux: -N 1
#flux: -n 4
#flux: -t 3h

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

s_pushd $ROOT_DIR/apps/unet3d
    export APP_ID="unet3d/normal"
    export TSTAMP=$(get_tstamp_uniq)
    export BASE_OUTPUT_DIR=/p/lustre5/iopp/rayandrew/dfprofiler/results/$APP_ID
    export OUTPUT=$BASE_OUTPUT_DIR/$TSTAMP
    export DATA_FOLDER=/p/lustre5/sinurat1/dataset/ml-workloads/unet3d

    set_dftracer_env

    log "Data folder      = $DATA_FOLDER"
    log "Output folder    = $OUTPUT"

    mkdir -p $OUTPUT

    # export MASTER_ADDR=$(flux getattr hostlist | /bin/hostlist -n 1)
    # export MASTER_PORT=23456
    # read TOTAL_GPUS TOTAL_NODES < <(flux resource list -no "{ngpus} {nnodes}")
    # NGPUS_PER_NODE=$((TOTAL_GPUS / TOTAL_NODES))
    # NPROCS=$TOTAL_GPUS

    # log "Master addresses = ${MASTER_ADDR}:${MASTER_PORT}"
    # log "Total nodes      = ${TOTAL_NODES}"
    # log "NGPUs per node   = ${NGPUS_PER_NODE}"
    # log "Num processes    = ${NPROCS}"

    SEED=${1:--1}

    # MAX_TRAINING_STEP=20
    MAX_TRAINING_STEP=-1

    MAX_EPOCHS=${EPOCHS:-1}
    QUALITY_THRESHOLD="0.908"
    START_EVAL_AT=10
    EVALUATE_EVERY=8
    LEARNING_RATE="0.8"
    LR_WARMUP_EPOCHS=200
    DATASET_DIR=$DATA_FOLDER
    BATCH_SIZE=2
    GRADIENT_ACCUMULATION_STEPS=1
    NUM_WORKERS=${NUM_WORKERS:-4}
    SLEEP=${SLEEP:--1}
    OUTPUT_DIR=$OUTPUT
    NPROC=${NPROC:-1}
    echo "{
    MAX_EPOCHS: ${MAX_EPOCHS},
    QUALITY_THRESHOLD: ${QUALITY_THRESHOLD},
    START_EVAL_AT: ${START_EVAL_AT},
    EVALUATE_EVERY: ${EVALUATE_EVERY},
    LEARNING_RATE: ${LEARNING_RATE},
    LR_WARMUP_EPOCHS: ${LR_WARMUP_EPOCHS},
    DATASET_DIR: ${DATASET_DIR},
    BATCH_SIZE: ${BATCH_SIZE},
    GRADIENT_ACCUMULATION_STEPS: ${GRADIENT_ACCUMULATION_STEPS},
    NUM_WORKERS: ${NUM_WORKERS},
    HOSTNAME: ${HOSTNAME},
    SLEEP: ${SLEEP},
    OUTPUT_DIR: ${OUTPUT_DIR},
    MAX_TRAINING_STEP: ${MAX_TRAINING_STEP},
    }" >& ${OUTPUT_DIR}/config.json

    if [ -d ${DATASET_DIR} ]
    then
        # start timing
        start=$(date +%s)
        start_fmt=$(date +%Y-%m-%d\ %r)
        echo "STARTING TIMING RUN AT $start_fmt"
        echo "Number of data loader workers: ${NUM_WORKERS}"
    TOTAL_NODES=1
    PPN=$(num_accelerators)
    NPROCS=$((NPROC * PPN))

    print_rocm_env

    flux run -N $TOTAL_NODES -o mpibind=off --exclusive rm -rf ${MIOPEN_USER_DB_PATH}
    # log DEBUG "Creating MIOpen cache directories on compute nodes"
    flux run -N $TOTAL_NODES -o mpibind=off --exclusive mkdir -p ${MIOPEN_USER_DB_PATH}

    flux run -N $TOTAL_NODES -n $NPROCS --exclusive -o fastload=on \
        python3 train.py \
        --data_dir ${DATASET_DIR} \
        --epochs ${MAX_EPOCHS} \
        --evaluate_every ${EVALUATE_EVERY} \
        --start_eval_at ${START_EVAL_AT} \
        --quality_threshold ${QUALITY_THRESHOLD} \
        --batch_size ${BATCH_SIZE} \
        --optimizer sgd \
        --ga_steps ${GRADIENT_ACCUMULATION_STEPS} \
        --learning_rate ${LEARNING_RATE} \
        --seed ${SEED} \
        --lr_warmup_epochs ${LR_WARMUP_EPOCHS} \
        --num_workers ${NUM_WORKERS} \
        --output_dir ${OUTPUT_DIR} \
        --max-training-step ${MAX_TRAINING_STEP} \
        --sleep ${SLEEP} \
        --verbose 2>&1 | tee -a $OUTPUT/output.log
      # end timing
      end=$(date +%s)
      end_fmt=$(date +%Y-%m-%d\ %r)
      echo "ENDING TIMING RUN AT $end_fmt"
    else
      echo "Directory ${DATASET_DIR} does not exist"
    fi

    link_latest $BASE_OUTPUT_DIR $OUTPUT
    # $DFTRACER_UTILS_BIN_DIR/dftracer_pgzip -d $OUTPUT
s_popd
