import os

import torch

from apps.unet3d.unet3d.runtime.distributed_utils import (
    get_rank,
    is_main_process,
    barrier,
)

def get_dllogger(params):
    import dllogger as logger
    from dllogger import StdOutBackend, Verbosity, JSONStreamBackend

    backends = []
    if is_main_process():
        backends += [StdOutBackend(Verbosity.VERBOSE)]
        if params.log_dir:
            backends += [
                JSONStreamBackend(
                    Verbosity.VERBOSE, os.path.join(params.log_dir, "log.json")
                )
            ]
    logger.init(backends=backends)
    return logger

def log_env_info():
    """
    Prints information about execution environment.
    """
    print("Collecting environment information...")
    env_info = torch.utils.collect_env.get_pretty_env_info()
    print(f"{env_info}")
