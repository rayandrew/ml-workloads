import os
import time

# LC HACK: work around so that "import torch" will not change CPU affinity
# see https://rzlc.llnl.gov/jira/browse/ELCAP-386
del os.environ["OMP_PLACES"]
del os.environ["OMP_PROC_BIND"]

from math import ceil

from apps.unet3d.unet3d.model.unet3d import Unet3D
from apps.unet3d.unet3d.model.losses import DiceCELoss, DiceScore

from apps.unet3d.unet3d.data_loading.data_loader import get_data_loaders

from apps.unet3d.unet3d.runtime.training import train
from apps.unet3d.unet3d.runtime.inference import evaluate
from apps.unet3d.unet3d.runtime.arguments import PARSER
from apps.unet3d.unet3d.runtime.distributed_utils import (
    init_distributed,
    deinit_distributed,
    get_device,
)
from apps.unet3d.unet3d.runtime.distributed_utils import seed_everything, setup_seeds
from apps.unet3d.unet3d.runtime.logging import (
    get_dllogger,
)
from apps.unet3d.unet3d.runtime.callbacks import get_callbacks

from src.mpi_utils import MPIUtils, get_master_addr_and_port
from src.logging import log0, configure_logging
from dftracer.python import dftracer, ai

DATASET_SIZE = 168
# DATASET_SIZE = 150000

@ai
def _main(flags):
    dllogger = get_dllogger(flags)
    local_rank = MPIUtils.local_rank()
    device = get_device(local_rank)
    is_distributed = init_distributed()
    world_size = MPIUtils.size()
    worker_seeds, shuffling_seeds = setup_seeds(flags.seed, flags.epochs, device)
    worker_seed = worker_seeds[local_rank]
    seed_everything(worker_seed)

    callbacks = get_callbacks(flags, dllogger, local_rank, world_size)
    flags.seed = worker_seed
    flags.shuffling_seed = shuffling_seeds[0]
    model = Unet3D(1, 3, normalization=flags.normalization, activation=flags.activation)

    train_dataloader, val_dataloader = get_data_loaders(
        flags, num_shards=world_size, global_rank=local_rank
    )
    samples_per_epoch = world_size * len(train_dataloader) * flags.batch_size
    flags.evaluate_every = flags.evaluate_every or ceil(
        20 * DATASET_SIZE / samples_per_epoch
    )
    flags.start_eval_at = flags.start_eval_at or ceil(
        1000 * DATASET_SIZE / samples_per_epoch
    )

    loss_fn = DiceCELoss(
        to_onehot_y=True,
        use_softmax=True,
        layout=flags.layout,
        include_background=flags.include_background,
    )
    score_fn = DiceScore(
        to_onehot_y=True,
        use_argmax=True,
        layout=flags.layout,
        include_background=flags.include_background,
    )

    def run():
        if flags.exec_mode == "train":
            t0 = time.time()
            train(
                flags,
                model,
                train_dataloader,
                val_dataloader,
                loss_fn,
                score_fn,
                device=device,
                callbacks=callbacks,
                is_distributed=is_distributed,
                sleep=flags.sleep,
            )
            t1 = time.time()
            if local_rank == 0:
                print("Total training time: %10.8f [s]" % (t1 - t0))
        elif flags.exec_mode == "evaluate":
            eval_metrics = evaluate(
                flags,
                model,
                val_dataloader,
                loss_fn,
                score_fn,
                device=device,
                is_distributed=is_distributed,
            )
            if local_rank == 0:
                for key in eval_metrics.keys():
                    print(key, eval_metrics[key])
        else:
            print("Invalid exec_mode.")
            pass

    if os.getenv("TORCH_PROFILER_ENABLE") == "1":
        from torch.profiler import profile, ProfilerActivity

        activities = [ProfilerActivity.CPU, ProfilerActivity.CUDA]
        with profile(activities=activities) as prof:
            run()
        prof.export_chrome_trace(
            f"{flags.output_dir}/torch-trace-{MPIUtils.rank()}-of-{MPIUtils.size()}.json"
        )
    else:
        run()

    deinit_distributed()

def main():
    flags = PARSER.parse_args()
    MPIUtils.initialize()
    hostname, port = get_master_addr_and_port(port=23456, set_env=True)
    configure_logging(output_dir=flags.output_dir)
    log0(f"MPI initialized. Master address: {hostname}:{port}")
    os.makedirs(flags.output_dir, exist_ok=True)
    flags.data_dir = os.path.abspath(flags.data_dir)
    dft = dftracer.initialize_log(
        f"{flags.output_dir}/trace-{MPIUtils.rank()}-of-{MPIUtils.size()}.pfw",
        flags.data_dir,
        process_id=MPIUtils.rank(),
    )
    _main(flags)
    dft.finalize()
    MPIUtils.finalize()


if __name__ == "__main__":
    main()
