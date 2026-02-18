#!/bin/bash

env_prelude() {
    log "Setting up environment on Corona"

    # tcsh users: to reinit modules for a bash script
    source /etc/profile.d/z00_lmod.sh

    module use /opt/toss/modules/modulefiles/

    require_module ninja

    # export ROCM_VERSION="6.0"
    export ROCM_VERSION="6.3.1"
    require_module rocm/$ROCM_VERSION

    export ROCM_HOME="${ROCM_PATH:-/opt/rocm-${ROCM_VERSION}}"

    export PATH="$ROCM_HOME/bin:$PATH"
    export CPATH="$ROCM_HOME/include:$CPATH"
    export DYLD_LIBRARY_PATH="$ROCM_HOME/lib:$DYLD_LIBRARY_PATH"
    export LD_LIBRARY_PATH="$ROCM_HOME/lib:$LD_LIBRARY_PATH"

    export GCC_VERSION="12.1.1"
    require_module gcc/$GCC_VERSION
    export CC=`which gcc`
    export CXX=`which g++`

    export PY_VERSION="3.10"
    require_module python/$PY_VERSION

    require_module cmake/3.23.1
    
    log "Forcing MPI compilers for installation $(which mpicc)"
    export CC=$(which mpicc)
    export CXX=$(which mpic++)
    export CMAKE_C_COMPILER=$(which mpicc)
    export CMAKE_CXX_COMPILER=$(which mpic++)

    assert "is_defined SYS_TYPE" "SYS_TYPE must be defined and not empty"

    # export LD_LIBRARY_PATH=/collab/usr/global/tools/rccl/${SYS_TYPE}_cray/rocm-$ROCM_VERSION/install/lib:$LD_LIBRARY_PATH
    export NCCL_NET_GDR_LEVEL=3
    export FI_CXI_ATS=0
    export NCCL_SOCKET_IFNAME=hsi0
}

env_create_venv() {
    assert "is_defined VENV_DIR" "VENV_DIR must be defined and not empty"
    if [[ ! -f $VENV_DIR/bin/python ]]; then
        # virtualenv --system-site-packages $VENV_DIR
        virtualenv $VENV_DIR
        python3 -m venv $VENV_DIR # --system-site-packages
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

    export TORCH_VERSION="2.5.1"

    log "Installing PyTorch for ROCM $ROCM_VERSION"
    pyver=$(normalize_python_version "$PY_VERSION")
    tmp_dir=$(get_tmp_dir)
    
    # files=(
    #     "torch-${TORCH_VERSION}%2Brocm${ROCM_VERSION}-cp${pyver}-cp${pyver}-linux_x86_64.whl"
    #     "torchvision-0.20.0%2Brocm${ROCM_VERSION}-cp${pyver}-cp${pyver}-linux_x86_64.whl"
    #     "torchaudio-2.5.0%2Brocm${ROCM_VERSION}-cp${pyver}-cp${pyver}-linux_x86_64.whl"
    #     "pytorch_triton_rocm-3.1.0%2Brocm${ROCM_VERSION}.ec5320655a-cp${pyver}-cp${pyver}-linux_x86_64.whl"
    # )

    # for file in "${files[@]}"; do
    #     if [ ! -f "$tmp_dir/$file" ]; then
    #         wget -O "$tmp_dir/$file" "https://repo.radeon.com/rocm/manylinux/rocm-rel-${ROCM_VERSION}/$file"
    #     fi
    # done

    # # Install all wheels in one pip command
    # pip install --no-cache-dir "${files[@]/#/$tmp_dir/}"
    # pip3 install --pre torch torchvision torchaudio --index-url "https://download.pytorch.org/whl/nightly/rocm$ROCM_VERSION"
    rocm_ver=$(echo $ROCM_VERSION | awk -F. '{print $1"."$2}')
    pip3 install --pre torch torchvision torchaudio pytorch-triton-rocm --index-url "https://download.pytorch.org/whl/nightly/rocm$rocm_ver"
}

need_tensorflow() {
    assert "is_defined ROCM_VERSION" "ROCM_VERSION must be defined and not empty, did you forget to call prelude()?"
    assert "is_defined PY_VERSION" "PY_VERSION must be defined and not empty, did you forget to call prelude()?"

    [[ -f "$VENV_DIR/lib/python$PY_VERSION/site-packages/tensorflow/libtensorflow_cc.so.2" ]] && return 0

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
    echo "8"
}
