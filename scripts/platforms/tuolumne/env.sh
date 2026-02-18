#!/bin/bash

env_prelude() {
    log "Setting up environment on Tuolumne"

    # tcsh users: to reinit modules for a bash script
    source /etc/profile.d/z00_lmod.sh

    module use /opt/toss/modules/modulefiles/

    require_module ninja

    # export ROCM_VERSION="6.0"
    export ROCM_VERSION="6.3.1"
    require_module rocm/$ROCM_VERSION

    require_module rccl

    export ROCM_HOME="${ROCM_PATH:-/opt/rocm-${ROCM_VERSION}}"

    export PATH="$ROCM_HOME/bin:$PATH"
    export CPATH="$ROCM_HOME/include:$CPATH"
    export DYLD_LIBRARY_PATH="$ROCM_HOME/lib:$DYLD_LIBRARY_PATH"
    export LD_LIBRARY_PATH="$ROCM_HOME/lib:$LD_LIBRARY_PATH"

    export GCC_VERSION="12.1"
    require_module gcc-native/$GCC_VERSION
    export CC=`which gcc`
    export CXX=`which g++`

    export PY_VERSION="3.11"
    require_module python/$PY_VERSION

    require_module cmake/3.23.1

    log "Forcing MPI compilers for installation $(which mpicc)"
    export CC=$(which mpicc)
    export CXX=$(which mpic++)
    export CMAKE_C_COMPILER=$(which mpicc)
    export CMAKE_CXX_COMPILER=$(which mpic++)
    # export CMAKE_BUILD_TYPE=Debug

    assert "is_defined SYS_TYPE" "SYS_TYPE must be defined and not empty"

    export LD_LIBRARY_PATH=/collab/usr/global/tools/rccl/${SYS_TYPE}/rocm-$ROCM_VERSION/install/lib:$LD_LIBRARY_PATH
    export NCCL_NET_GDR_LEVEL=3
    export FI_CXI_ATS=0

    export LD_LIBRARY_PATH=/opt/cray/pe/mpich/9.0.1/ofi/CRAYCLANG/20.0/lib/:$LD_LIBRARY_PATH
    # export NCCL_SOCKET_IFNAME=hsi0
    # export NCCL_SOCKET_IFNAME='hsi0,hsi1,hsi2,hsi3'
    # export NCCL_NSOCKS_PERTHREAD=8
    # export NCCL_SOCKET_NTHREADS=4
    # export HSA_XNACK=1  # Enable page migration for unified memory
    # export AMD_DIRECT_DISPATCH=0


    export MIOPEN_FIND_MODE=FAST
    export MIOPEN_ENABLE_LOGGING=0
    export MIOPEN_USER_DB_PATH="/tmp/miopen-cache"
    export MIOPEN_CUSTOM_CACHE_DIR=${MIOPEN_USER_DB_PATH}
    export MIOPEN_DEBUG_CONV_FFT=0
}

env_create_venv() {
    assert "is_defined VENV_DIR" "VENV_DIR must be defined and not empty"
    if [[ ! -f $VENV_DIR/bin/python ]]; then
        virtualenv $VENV_DIR
        python3 -m venv $VENV_DIR
    fi
}

need_pytorch() {
    assert "is_defined ROCM_VERSION" "ROCM_VERSION must be defined and not empty, did you forget to call prelude()?"
    assert "is_defined PY_VERSION" "PY_VERSION must be defined and not empty, did you forget to call prelude()?"
    if [[ -f "$VENV_DIR/lib/python$PY_VERSION/site-packages/torch/version.py" ]]; then
        log "PyTorch already installed"
        export LD_LIBRARY_PATH="$VENV_DIR/lib/python$PY_VERSION/site-packages/torch/lib:$LD_LIBRARY_PATH"
        return 0
    fi

    export TORCH_VERSION="2.8.0"

    log "Installing PyTorch for ROCM $ROCM_VERSION"
    pyver=$(normalize_python_version "$PY_VERSION")
    rocm_ver=$(echo $ROCM_VERSION | awk -F. '{print $1$2$3}')
    pip install torch==$TORCH_VERSION+rocm$rocm_ver torchvision torchaudio
}

need_tensorflow() {
    assert "is_defined ROCM_VERSION" "ROCM_VERSION must be defined and not empty, did you forget to call prelude()?"
    assert "is_defined PY_VERSION" "PY_VERSION must be defined and not empty, did you forget to call prelude()?"

    [[ -d "$VENV_DIR/lib/python$PY_VERSION/site-packages/tensorflow/xla_aot_runtime_src" ]] && return 0

    if is_version $ROCM_VERSION LESS_THAN "6.1"; then
        ## Since `corona` only supports 6.0.2, then we only stuck at TF_VERSION=2.14.0 without recompiling tensorflow

        ## see https://rocm.docs.amd.com/projects/install-on-linux/en/latest/install/3rd-party/tensorflow-install.html#install-tensorflow-versions
        ## and check the version of your ROCM
        ## here, we load 6.0.x and 2.14.0 is the latest version that it supports
        export TF_VERSION="2.14.0"
        export NP_VERSION="1.24.0"

        # Based on https://rocm.docs.amd.com/projects/install-on-linux/en/latest/install/3rd-party/tensorflow-install.html#using-a-wheels-package
        # The naming is different. prior to 6.1, we use <TensorFlowVersion>.<ROCmVersion> for the wheel name
        # so we need to normalize it
        NORM_ROCM_VERSION=$(normalize_rocm_wheel_version_for_tensorflow "$ROCM_VERSION")
        TF_ROCM_WHEEL_VERSION="$TF_VERSION.$NORM_ROCM_VERSION"

        log "Installing Tensorflow"
        pip install tensorflow-rocm==$TF_ROCM_WHEEL_VERSION --upgrade

        log "Downgrading numpy to $NP_VERSION for compatibility"
        pip install numpy==$NP_VERSION # this version able to support this numpy only
    elif is_version $ROCM_VERSION LESS_THAN "6.4"; then
        log "Installing Tensorflow for ROCM $ROCM_VERSION"
        export TF_VERSION="2.17.0"
        pyver=$(normalize_python_version "$PY_VERSION")
        tmp_dir=$(get_tmp_dir)
        file="tensorflow_rocm-${TF_VERSION}-cp${pyver}-cp${pyver}-manylinux_2_28_x86_64.whl"
        if [ ! -f "$tmp_dir/$file" ]; then
            wget -O "$tmp_dir/$file" "https://repo.radeon.com/rocm/manylinux/rocm-rel-${ROCM_VERSION}/${file}"
        fi
        pip install "$tmp_dir/$file"
    else
        todo "tensorflow for rocm >= 6.4"
    fi
}

need_horovod() {
    # TODO: enable NCCL if we can
    # export HOROVOD_WITH_MPI=1
    # export HOROVOD_GPU="ROCM"
    # export HOROVOD_GPU_OPERATIONS="NCCL"
    # export HOROVOD_WITHOUT_PYTORCH=1
    # export HOROVOD_WITHOUT_MXNET=1
    need_python_pkg pkg=horovod
    # unset HOROVOD_GPU
    # unset HOROVOD_GPU_OPERATIONS
    # unset HOROVOD_WITH_MPI
}

num_accelerators() {
    echo "4"
}
