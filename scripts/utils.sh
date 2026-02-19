#!/bin/bash

####################################################################################
# General Utilities
####################################################################################

## Colors taken from
## https://github.com/saforem2/ezpz/blob/361e6bd8b4873c50b84152f9e4cce20003eecf18/src/ezpz/bin/utils.sh#L27

if [[ -n "${NO_COLOR:-}" || -n "${NOCOLOR:-}" || "${COLOR:-}" == 0 || "${TERM}" == "dumb" ]]; then
    # Enable color support for `ls` and `grep`
    # shopt -s dircolors
    # shopt -s colorize
    # exitpt -s colorize_grep
    export RESET=''
    export BLACK=''
    export RED=''
    export BRIGHT_RED=''
    export GREEN=''
    export BRIGHT_GREEN=''
    export YELLOW=''
    export BRIGHT_YELLOW=''
    export BLUE=''
    export BRIGHT_BLUE=''
    export MAGENTA=''
    export BRIGHT_MAGENTA=''
    export CYAN=''
    export BRIGHT_CYAN=''
    export WHITE=''
    export BRIGHT_WHITE=''
else
    # --- Color Codes ---
    # Usage: printf "${RED}This is red text${RESET}\n"
    export RESET='\e[0m'
    # BLACK='\e[1;30m' # Avoid black text
    export RED='\e[1;31m'
    export BRIGHT_RED='\e[1;91m' # Added for emphasis
    export GREEN='\e[1;32m'
    export BRIGHT_GREEN='\e[1;92m' # Added for emphasis
    export YELLOW='\e[1;33m'
    export BRIGHT_YELLOW='\e[1;93m' # Added for emphasis
    export BLUE='\e[1;34m'
    export BRIGHT_BLUE='\e[1;94m' # Added for emphasis
    export MAGENTA='\e[1;35m'
    export BRIGHT_MAGENTA='\e[1;95m' # Added for emphasis
    export CYAN='\e[1;36m'
    export BRIGHT_CYAN='\e[1;96m' # Added for emphasis
    export WHITE='\e[1;37m'       # Avoid white on light terminals
    export BRIGHT_WHITE='\e[1;97m' # Added for emphasis
fi

DEFAULT_LOG_LEVEL="${DEFAULT_LOG_LEVEL:-INFO}"
export DEFAULT_LOG_LEVEL

log() {
    local level
    local string
    local ts
    ts=$(get_tstamp_ns)

    # Check if the first argument is a log level
    case "$1" in
        DEBUG|INFO|WARN|ERROR|FATAL)
            level="$1"
            shift
            string="$*"
            ;;
        *)
            level="$DEFAULT_LOG_LEVEL"
            string="$*"
            ;;
    esac

    local log_level
    case "${level}" in
        DEBUG) log_level="${CYAN}DBG${RESET}" ;;
        INFO) log_level="${GREEN}INF${RESET}" ;;
        WARN) log_level="${YELLOW}WRN${RESET}" ;;
        ERROR) log_level="${RED}ERR${RESET}" ;;
        FATAL) log_level="${BRIGHT_RED}FTL${RESET}" ;;
        *) log_level="${GREEN}INF${RESET}" ;; # Default to INFO
    esac

    log_msg="[${log_level}][${BRIGHT_BLUE}${ts}${RESET}] ${string}"
    # Redirect ERROR and FATAL to stderr
    if [[ "$level" == "ERROR" || "$level" == "FATAL" ]]; then
        echo -e "$log_msg" >&2
    elif [[ "$level" == "DEBUG" ]]; then
        if is_debug_mode; then
            echo -e "$log_msg"
        fi
    else
        echo -e "$log_msg"
    fi
}

argparse() {
    local key="$1"
    local __resultvar="$2"
    local validation="$3"
    local __argsvar="$4"

    local -n args_ref="$__argsvar"

    local value=""
    local found=false

    for i in "${!args_ref[@]}"; do
        if [[ "${args_ref[i]}" == "$key="* ]]; then
            value="${args_ref[i]#${key}=}"
            [[ "$value" =~ ^\".*\"$ || "$value" =~ ^\'.*\'$ ]] && value="${value:1:-1}"
            printf -v "$__resultvar" "%s" "$value"
            # remove parsed arg
            unset 'args_ref[i]'
            args_ref=("${args_ref[@]}")
            return 0
        fi
    done

    case "$validation" in
        required)
            log ERROR "Required argument '$key' is missing" >&2
            exit 1
            ;;
        default:*)
            local default_value="${validation#default:}"
            printf -v "$__resultvar" "%s" "$default_value"
            return 0
            ;;
        optional)
            printf -v "$__resultvar" ""
            return 0
            ;;
        *)
            log ERROR "Invalid validation type: $validation" >&2
            exit 1
            ;;
    esac
}

get_tstamp_ns() {
    date "+%Y-%m-%d %H:%M:%S,%N"
}

get_tstamp() {
    date "+%Y-%m-%d-%H-%M-%S"
}

get_random_id() {
    head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8
}

get_tstamp_uniq() {
    echo "$(date "+%Y-%m-%d-%H-%M-%S")-$$-$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 4)"
}

is_defined() {
    local var="$1"
    [[ -n "${!var+x}" && -n "${!var}" ]]
}

is_truthy() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes) return 0 ;;
        *) return 1 ;;
    esac
}

is_falsy() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
        0|false|no|"") return 0 ;;
        *) return 1 ;;
    esac
}

is_debug_mode() {
    is_truthy "$DEBUG_MODE"
}

assert() {
    if ! eval "$1"; then
        log ERROR "Assertion failed: ${2:-$1}" >&2
        exit 1
    fi
}

todo() {
    local file="${BASH_SOURCE[1]}"
    local line="${BASH_LINENO[0]}"

    if [[ $# -eq 0 ]]; then
        log ERROR "Not implemented yet at $file:$line"
    else
        log ERROR "$1: not implemented yet at $file:$line"
    fi
    exit 1
}

s_pushd() {
    pushd "$@" > /dev/null 2>&1
    local new_dir="$PWD"
    log "Entering \"$new_dir\""
}

s_popd() {
    local prev_dir="$PWD"
    # Perform popd
    popd "$@" > /dev/null 2>&1
    log "Exiting \"$prev_dir\""
}

glob_disable() {
    set -f
}

glob_enable() {
    set +f
}

get_cluster_name() {
    hm=$(hostname)
    if [[ "$hm" == *"corona"* ]]; then
        echo "corona"
    elif [[ "$hm" == *"tuolumne"* ]]; then
        echo "tuolumne"
    else
        echo "unknown"
    fi
}

get_lustre_loc() {
    cluster=$(get_cluster_name)
    if [[ $cluster == "corona" ]]; then
        echo "/p/lustre3"
    elif [[ $cluster == "tuolumne" ]]; then
        echo "/p/lustre5"
    else
        echo "unknown"
    fi
}
get_lustre_user_loc() {
    cluster=$(get_cluster_name)
    if [[ $cluster == "corona" ]]; then
        echo "/p/lustre3/$USER"
    elif [[ $cluster == "tuolumne" ]]; then
        echo "/p/lustre5/$USER"
    else
        echo "unknown"
    fi
}

####################################################################################
# Modules and Package Utilities
####################################################################################

load_module() {
    local module="$1"
    local fatal="$2"

    log "Loading module $module"
    if is_debug_mode; then
        module load $module
    else
        module load $module > /dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            log ERROR "┗━━ Failed to load module $module"
            if is_truthy "$fatal"; then
                exit 1
            fi
        else
            log "┗━━ Successfully load module $module"
        fi
    fi
}

require_module() {
    local module="$1"
    load_module "$module" 1
}

normalize_rocm_wheel_version_for_tensorflow() {
    local version="${1//\"/}"
    IFS='.' read -r -a parts <<< "$version"

    local major="${parts[0]:-0}"
    local minor="${parts[1]:-0}"
    local patch="${parts[2]:-0}"

    local norm="${major}${minor}${patch}"

    while [[ ${#norm} -lt 3 ]]; do
        norm="${norm}0"
    done

    echo "$norm"
}

normalize_python_version() {
    local version="${1//\"/}"
    IFS='.' read -r -a parts <<< "$version"

    local major="${parts[0]:-0}"
    local minor="${parts[1]:-0}"

    local norm="${major}${minor}"

    echo "$norm"
}

is_version() {
    local v1="${1//\"/}"
    local op="$2"
    local v2="${3//\"/}"

    # Split into arrays
    IFS='.' read -r -a a1 <<< "$v1"
    IFS='.' read -r -a a2 <<< "$v2"

    # Pad missing parts with zeros
    for i in 0 1 2; do
        a1[$i]=${a1[$i]:-0}
        a2[$i]=${a2[$i]:-0}
    done

    # Compose comparable numbers
    local n1=$((10#${a1[0]} * 100 + 10#${a1[1]} * 10 + 10#${a1[2]}))
    local n2=$((10#${a2[0]} * 100 + 10#${a2[1]} * 10 + 10#${a2[2]}))

    case "$op" in
        LESS_THAN)
            [[ $n1 -lt $n2 ]]
            ;;
        LESS_EQUAL)
            [[ $n1 -le $n2 ]]
            ;;
        GREATER_THAN)
            [[ $n1 -gt $n2 ]]
            ;;
        GREATER_EQUAL)
            [[ $n1 -ge $n2 ]]
            ;;
        EQUAL)
            [[ $n1 -eq $n2 ]]
            ;;
        *)
            echo "Invalid operator: $op" >&2
            return 2
            ;;
    esac
}

# Function: check_py_pkg
# Purpose: Check if a Python package directory exists in the site-packages directory
# Usage: check_py_pkg pkg=<package_name> [id=<package_id>]
# Requirements:
#   - PY_VERSION environment variable must be set (e.g., "3.10")
#   - The corresponding python executable (e.g., python3.10) must be available
check_py_pkg() {
    assert "is_defined PY_VERSION" "PY_VERSION must be defined and not empty"

    local args=("$@")
    local pkg identifier
    argparse "pkg" pkg required args
    argparse "id" identifier optional args

    local pkg_name="$pkg"
    local id="$identifier"
    local py_exec="python${PY_VERSION}"

    if [ -z "$id" ]; then
        id="$pkg_name"
    fi

    # Get the site-packages directory for the specified Python version
    local site_packages_dir
    site_packages_dir=$($py_exec -c "import site; print(site.getsitepackages()[0])" 2>/dev/null)

    # Check if the python executable and site-packages directory were found
    if [ -z "$site_packages_dir" ] || [ ! -d "$site_packages_dir" ]; then
        log ERROR "Error: Could not determine site-packages for Python $PY_VERSION."
        return 3
    fi

    if [ -f "$site_packages_dir/$id.py" ] || [ -f "$site_packages_dir/$id" ]; then
        # Check if the package file exists in site-packages
        return 0
    elif [ -d "$site_packages_dir/$id" ]; then
        # Check if the package directory exists in site-packages
        return 0
    else
        # log ERROR "Package '$pkg_name' is NOT installed in Python $PY_VERSION."
        return 4
    fi
}

# Function: check_py_pkg_or_exit
# Purpose: Check if a Python package is installed; exit script if not found
# Usage: check_py_pkg_or_exit pkg=<package_name> [id=<package_id>]
check_py_pkg_or_exit() {
    # Call the check_py_pkg function with the given package name
    check_py_pkg $@
    local status=$?
    if [ $status -eq 4 ]; then
        log ERROR "Exiting: Required Python package '$1' is not installed."
        exit 1
    elif [ $status -ne 0 ]; then
        log ERROR "Exiting: Error occurred during package check."
        exit $status
    fi
}

# Function: need_python_pkg
# Purpose: Ensure a Python package is installed; install if missing
# Usage: need_python_pkg pkg=<package_name> [id=<package_id>] [editable=true]
need_python_pkg() {
    assert "is_defined PY_VERSION" "PY_VERSION must be defined and not empty"

    local args=("$@")
    local pkg id editable force
    argparse "pkg" pkg required args
    argparse "id" id optional args
    argparse "editable" editable optional args
    argparse "force" force default:0 args

    if [ -z "$id" ]; then
        id="$pkg"
    fi

    if is_truthy "$force"; then
        log DEBUG "Forcing reinstallation of Python package '$pkg'."
        if is_truthy "$editable"; then
            python${PY_VERSION} -m pip install -e "$pkg" "${args[@]}"
        else
            python${PY_VERSION} -m pip install "$pkg" "${args[@]}"
        fi
    else
        check_py_pkg pkg="$pkg" id="$id"
        local status=$?
        if [ $status -eq 0 ]; then
            log DEBUG "Python package '$pkg' is already installed. Exiting."
        elif [ $status -eq 4 ]; then
            log "Python package '$pkg' is not installed. Installing..."
            # Attempt to install the package
            if is_truthy "$editable"; then
                python${PY_VERSION} -m pip install -e "$pkg" "${args[@]}"
            else
                python${PY_VERSION} -m pip install "$pkg" "${args[@]}"
            fi

            if [ $? -eq 0 ]; then
                log "Successfully installed '$pkg'."
            else
                log ERROR "Failed to install '$pkg'."
                exit 3
            fi
        else
            log ERROR "Error occurred during package check."
            exit $status
        fi
    fi
}

####################################################################################
# Packages
####################################################################################

# Function: need_mpi4py
# Purpose: Ensure `mpi4py` is installed with appropriate flags
need_mpi4py() {
    assert "is_defined VENV_DIR" "VENV_DIR must be defined and not empty"
    assert "is_defined PY_VERSION" "PY_VERSION must be defined and not empty"


    merged_python_ver="${PY_VERSION//./}"
    if [[ -f "${VENV_DIR}/lib/python${PY_VERSION}/site-packages/mpi4py/MPI.cpython-${merged_python_ver}-x86_64-linux-gnu.so" ]]; then
        return
    fi
    pip install --no-binary=mpi4py mpi4py --force-reinstall
    # pip install mpi4py==4.1.0.dev0+mpich.8.1.32
}

# Function: need_dftracer
# Purpose: Ensure `dftracer` is installed
need_dftracer() {
    local args=("$@")
    local is_development dev_path force ftracing hip_tracing
    argparse "dev" is_development optional args
    argparse "dev_path" dev_path default:"/usr/workspace/sinurat1/dftracer" args
    argparse "force" force default:0 args
    argparse "ftracing" ftracing default:0 args
    argparse "hip_tracing" hip_tracing default:0 args

    if is_truthy $hip_tracing; then
        export DFTRACER_ENABLE_HIP_TRACING=ON
    fi
    if is_truthy $ftracing; then
        export DFTRACER_ENABLE_FTRACING=ON
    fi

    merged_python_ver="${PY_VERSION//./}"
    if is_truthy $is_development; then
        need_python_pkg pkg="$dev_path" id="dftracer/dftracer.cpython-$merged_python_ver-x86_64-linux-gnu.so" force="$force"
    else
      hash="paper/dfprofiler"
      need_python_pkg pkg="git+https://github.com/LLNL/dftracer@$hash" id="dftracer/dftracer.cpython-$merged_python_ver-x86_64-linux-gnu.so"  force="$force"
    fi

    if is_truthy $hip_tracing; then
        unset DFTRACER_ENABLE_HIP_TRACING
    fi
    if is_truthy $ftracing; then
        unset DFTRACER_ENABLE_FTRACING
    fi
}

# Function: need_pydftracer
# Purpose: Ensure `pydftracer` is installed
need_pydftracer() {
    local args=("$@")
    local is_development dev_path force
    argparse "dev" is_development optional args
    argparse "dev_path" dev_path default:"/usr/workspace/sinurat1/pydftracer" args

    if is_truthy $is_development; then
        need_python_pkg pkg="$dev_path" force="$force"
    else
      hash="develop"
      need_python_pkg pkg="git+https://github.com/rayandrew/pydftracer@$hash" id="dftracer/logger" force="$force"
    fi
}

# Function: need_dlio_deps
# Purpose: Ensure `dlio` dependencies are installed
need_dlio_deps() {
    local args=("$@")
    local is_dftracer_development dftracer_dev_path
    argparse "dftracer_dev" is_dftracer_development optional args
    argparse "dftracer_dev_path" dftracer_dev_path default:"/usr/workspace/sinurat1/dftracer" args

    need_pytorch
    need_tensorflow

    need_python_pkg pkg="Pillow>=9.3.0" id="PIL"
    need_python_pkg pkg="PyYAML~=6.0.0" id="yaml"
    need_python_pkg pkg="hydra-core==1.3.2" id="hydra"

    need_pydftracer
    need_dftracer # dev=$is_dftracer_development dev_path=$dftracer_dev_path

    need_python_pkg pkg="psutil>=5.9.8" id="psutil"
    # need_python_pkg pkg="torch" id="torch" --index-url https://download.pytorch.org/whl/cpu
    # need_python_pkg pkg="torchvision" id="torchvision" --index-url https://download.pytorch.org/whl/cpu
    # need_python_pkg pkg="torchaudio" id="torchaudio" --index-url https://download.pytorch.org/whl/cpu
    # need_python_pkg pkg="tensorflow-cpu" id="tensorflow"
    # need_python_pkg pkg="tensorflow_io"
    need_python_pkg pkg="tqdm"
    need_python_pkg pkg="pandas"
    need_python_pkg pkg="nvidia-dali-cuda120>=1.34.0" id="nvidia/dali"
    need_mpi4py
}

# Function: need_dlio
# Purpose: Ensure `dlio` is installed
need_dlio() {
    local args=("$@")
    local is_development dev_path dftracer_dev_path is_dftracer_development force
    argparse "dev" is_development optional args
    argparse "dev_path" dev_path default:"/usr/workspace/sinurat1/dlio_benchmark_dev" args
    argparse "dftracer_dev" is_dftracer_development optional args
    argparse "dftracer_dev_path" dftracer_dev_path default:"/usr/workspace/sinurat1/dftracer" args
    argparse "force" force default:0 args

    need_dlio_deps dftracer_dev=$is_dftracer_development dftracer_dev_path=$dftracer_dev_path

    if is_truthy $is_development; then
        need_python_pkg pkg="$dev_path" id="dlio_benchmark-2.0.0.dist-info" editable=true force="$force"
    else
        need_python_pkg pkg="git+https://github.com/argonne-lcf/dlio_benchmark" id="dlio_benchmark" force="$force"
    fi
}

# Function: need_mlperf_logging
# Purpose: Install mlperf logging package
need_mlperf_logging() {
    local args=("$@")
    local hash
    argparse "hash" hash default:"346e6046e16148ed095ffce5d9650f20e83b6858" args
    need_python_pkg pkg="git+https://github.com/mlperf/logging.git@$hash" id="mlperf_logging"
}

# Function: need_dllogger
# Purpose: Install dllogger package
need_dllogger() {
    local args=("$@")
    local hash
    argparse "hash" hash default:"0478734ff7be75adde8d160e04872664d1c62e5f" args
    need_python_pkg pkg="git+https://github.com/NVIDIA/dllogger@$hash#egg=dllogger" id="dllogger"
}

####################################################################################
# Experiment Utilities
####################################################################################

# Function: dftracer_preload_loc
# Purpose: Locate the dftracer preload library
# Usage: dftracer_lib=$(dftracer_preload_loc)
dftracer_preload_loc() {
    assert "is_defined VENV_DIR" "VENV_DIR must be defined and not empty"
    assert "is_defined PY_VERSION" "PY_VERSION must be defined and not empty"

    if [[ -f "${VENV_DIR}/lib/python${PY_VERSION}/site-packages/dftracer/lib64/libdftracer_preload.so" ]]; then
        echo "${VENV_DIR}/lib/python${PY_VERSION}/site-packages/dftracer/lib64/libdftracer_preload.so"
    elif [[ -f "${VENV_DIR}/lib/python${PY_VERSION}/site-packages/dftracer/lib/libdftracer_preload.so" ]]; then
        echo "${VENV_DIR}/lib/python${PY_VERSION}/site-packages/dftracer/lib/libdftracer_preload.so"
    else
        log ERROR "dftracer preload lib -- NOT FOUND, exiting..."
        exit 1
    fi
}

# Function: set_dftracer_env
# Purpose: Set the environment variables for dftracer
set_dftracer_env() {
    if is_truthy $DISABLE_DFTRACER; then
        log INFO "dftracer is disabled"
        return
    fi
    check_py_pkg pkg=dftracer id=dftracer

    export DFTRACER_ENABLE=1
    export DFTRACER_INC_METADATA=1
    export DFTRACER_PRELOAD=$(dftracer_preload_loc)
    export LD_PRELOAD="${DFTRACER_PRELOAD}:${LD_PRELOAD}"
    log "DFTracer"
    log "┣━━ Enabled      = 1"
    log "┣━━ Inc Metadata = 1"
    log "┗━━ Preload      = $DFTRACER_PRELOAD"
}

link_latest() {
    local base_dir=$1
    local dir=$2
    if [[ -f $base_dir/latest ]]; then
        rm -f $base_dir/latest
    fi
    ln -sfn $dir $base_dir/latest
}

link_main() {
    local base_dir=$1
    local dir=$2
    if [[ -f $base_dir/main ]]; then
        rm -f $base_dir/main
    fi
    ln -sfn $dir $base_dir/main
}

get_tmp_dir() {
    assert "is_defined ROOT_DIR" "ROOT_DIR must be defined and not empty"
    tmp="$ROOT_DIR/tmp"
    mkdir -p "$tmp"
    echo "$tmp"
}

dump_env() {
    local args=("$@")
    local file
    argparse "file" file optional args
    env | sort > "${file:-/dev/stdout}"
}

dump_str() {
    local args=("$@")
    local file
    argparse "file" file optional args
    echo "$*" > "${file:-/dev/stdout}"
}

mkhostfile() {
    local args=("$@")
    local id
    argparse "id" id optional args
    if [[ -n $id ]]; then
      hostfile=$(mktemp --suffix=".hostfile" $id.XXXXXX)
    else
      hostfile=$(mktemp --suffix=".hostfile" XXXXXX)
    fi

    flux hostlist -led'\n' > $hostfile
    echo "$hostfile"
}

need_dftracer_utils() {
  assert "is_defined ROOT_DIR" "ROOT_DIR must be defined and not empty"
  # check if dftracer-utils dir exists
  cluster=$(get_cluster_name)
  dftracer_utils_dir="$ROOT_DIR/tools/$cluster/dftracer-utils"
  if [[ ! -d $dftracer_utils_dir ]]; then
      mkdir -p $dftracer_utils_dir
      git clone git@github.com:rayandrew/dftracer-utils.git $dftracer_utils_dir
      s_pushd $dftracer_utils_dir
        git checkout feat/future-ideas
      s_popd
  fi

  s_pushd $dftracer_utils_dir
    if [[ ! -f "build/bin/dftracer_aggregator" ]]; then
        mkdir -p build
        s_pushd build
            cmake .. -DCMAKE_BUILD_TYPE=Release
            make -j$(nproc)
        s_popd
    fi
  s_popd

  export DFTRACER_UTILS_DIR=$(realpath $dftracer_utils_dir)
  export DFTRACER_UTILS_BIN_DIR="$dftracer_utils_dir/build/bin"
  export PATH="$PATH:$DFTRACER_UTILS_DIR"
}

need_flash_attn() {
    assert "is_defined VENV_DIR" "VENV_DIR must be defined and not empty"
    assert "is_defined PY_VERSION" "PY_VERSION must be defined and not empty"
    assert "is_defined ROOT_DIR" "ROOT_DIR must be defined and not empty"

    if [[ -d "${VENV_DIR}/lib/python${PY_VERSION}/site-packages/flash_attn" ]]; then
        log INFO "flash_attn is already installed"
        return
    fi

    cluster=$(get_cluster_name)
    flash_attn_dir="$ROOT_DIR/tmp/flash_attn/$cluster"
    if [[ ! -d $flash_attn_dir ]]; then
        mkdir -p $ROOT_DIR/tmp/flash_attn
        git clone --recursive https://github.com/ROCm/flash-attention.git $flash_attn_dir
    fi

    s_pushd $flash_attn_dir
        MAX_JOBS=$((`nproc` - 1)) pip install -v .
    s_popd

    log INFO "flash_attn installation complete"
}

need_aws_ofi_rccl() {
  assert "is_defined ROCM_VERSION" "ROCM_VERSION must be defined and not empty"
  cluster=$(get_cluster_name)

  if [[ $cluster == "tuolumne" ]]; then
      require_module craype-accel-amd-gfx942
  fi

  export libfabric_path=/opt/cray/libfabric/2.0
  aws_ofi_rccl_dir="$ROOT_DIR/tmp/aws-ofi-rccl/$cluster"

  if [[ -d $aws_ofi_rccl_dir/lib ]]; then
        export LD_LIBRARY_PATH=$aws_ofi_rccl_dir/lib:$LD_LIBRARY_PATH
        return
  fi

  if [[ ! -d $aws_ofi_rccl_dir ]]; then
      git clone --recursive https://github.com/ROCmSoftwarePlatform/aws-ofi-rccl $aws_ofi_rccl_dir
  fi

  s_pushd $aws_ofi_rccl_dir
      ./autogen.sh

      export LD_LIBRARY_PATH=/opt/rocm-$ROCM_VERSION/hip/lib:$LD_LIBRARY_PATH

      CC=hipcc CXX=hipcc CFLAGS=-I/opt/rocm-$ROCM_VERSION/rccl/include ./configure --with-libfabric=$libfabric_path --with-rccl=/opt/rocm-$ROCM_VERSION --prefix=$aws_ofi_rccl_dir --with-hip=/opt/rocm-$ROCM_VERSION/hip --with-mpi=$MPICH_DIR
      make
      make install
  s_popd
}

print_rocm_env() {
  if [[ -f "$ROCM_HOME/lib/libMIOpen.so.1" ]]; then
    does_miopen_lib_exist="Yes"
  else
    does_miopen_lib_exist="No"
  fi
  log "ROCm Environment:"
  log "┣━━ ROCM_HOME                   = $ROCM_HOME"
  log "┣━━ ROCM_PATH                   = $ROCM_PATH"
  log "┣━━ MIOPEN_USER_DB_PATH         = $MIOPEN_USER_DB_PATH"
  # log "┣━━ MIOPEN_SYSTEM_DB_PATH       = $MIOPEN_SYSTEM_DB_PATH"
  log "┣━━ MIOPEN_CUSTOM_CACHE_DIR     = $MIOPEN_CUSTOM_CACHE_DIR"
  log "┣━━ LD_LIBRARY_PATH (ROCm part) = $(echo $LD_LIBRARY_PATH | tr ':' '\n' | grep rocm | head -3 | tr '\n' ':')"
  log "┣━━ MIOpen lib exists           = $does_miopen_lib_exist"
}
