import os
import time
import logging

import torch
from torch.optim import Adam, SGD
from torch.amp import autocast, GradScaler
import numba

from tqdm import tqdm

from apps.unet3d.unet3d.runtime.distributed_utils import (
    get_rank,
    reduce_tensor,
    get_world_size,
)
from apps.unet3d.unet3d.runtime.inference import evaluate

from dftracer.python import ai

log = logging.getLogger(__name__)

skip_reduce = False
try:
    if os.environ["SKIP_REDUCE"] == "1":
        print("skip_reduce")
        skip_reduce = True
except:
    skip_reduce = False


def emulate_compute(device, sec):
    if str(device).find("GPU") != -1:
        print("Putting GPU into sleep for %10.5f sec" % sec)
        numba.cuda.nanosleep(sec * 1000000000)
    else:
        time.sleep(sec)


def get_optimizer(params, flags):
    if flags.optimizer == "adam":
        optim = Adam(params, lr=flags.learning_rate, weight_decay=flags.weight_decay)
    elif flags.optimizer == "sgd":
        optim = SGD(
            params,
            lr=flags.learning_rate,
            momentum=flags.momentum,
            nesterov=True,
            weight_decay=flags.weight_decay,
        )
    elif flags.optimizer == "lamb":
        import apex

        optim = apex.optimizers.FusedLAMB(
            params,
            lr=flags.learning_rate,
            betas=flags.lamb_betas,
            weight_decay=flags.weight_decay,
        )
    else:
        raise ValueError("Optimizer {} unknown.".format(flags.optimizer))
    return optim


def lr_warmup(optimizer, init_lr, lr, current_epoch, warmup_epochs):
    scale = current_epoch / warmup_epochs
    for param_group in optimizer.param_groups:
        param_group["lr"] = init_lr + (lr - init_lr) * scale


@ai.pipeline.train
def train(
    flags,
    model,
    train_loader,
    val_loader,
    loss_fn,
    score_fn,
    device,
    callbacks,
    is_distributed,
    sleep=-1,
):
    rank = get_rank()
    world_size = get_world_size()
    torch.backends.cudnn.benchmark = flags.cudnn_benchmark
    torch.backends.cudnn.deterministic = flags.cudnn_deterministic
    optimizer = get_optimizer(model.parameters(), flags)
    if flags.lr_decay_epochs:
        scheduler = torch.optim.lr_scheduler.MultiStepLR(
            optimizer, milestones=flags.lr_decay_epochs, gamma=flags.lr_decay_factor
        )
    scaler = GradScaler()

    model.to(device)
    loss_fn.to(device)
    if is_distributed:
        model = torch.nn.parallel.DistributedDataParallel(
            model, device_ids=[flags.local_rank], output_device=flags.local_rank
        )

    is_successful = False
    diverged = False
    next_eval_at = flags.start_eval_at
    model.train()

    for callback in callbacks:
        callback.on_fit_start()
    for epoch in ai.pipeline.epoch.iter(
        range(1, flags.epochs + 1),
        include_iter=False,
    ):
        ai.update(epoch=epoch)
        cumulative_loss = []
        if epoch <= flags.lr_warmup_epochs and flags.lr_warmup_epochs > 0:
            lr_warmup(
                optimizer,
                flags.init_learning_rate,
                flags.learning_rate,
                epoch,
                flags.lr_warmup_epochs,
            )

        if is_distributed:
            train_loader.sampler.set_epoch(epoch)

        loss_value = None
        optimizer.zero_grad()
        for iteration, batch in ai.dataloader.fetch.iter(
            enumerate(tqdm(train_loader, disable=(rank != 0) or not flags.verbose))
        ):
            if flags.max_training_step != -1 and iteration >= flags.max_training_step:
                break
            ai.update(epoch=epoch, step=iteration + 1)
            image, label = batch
            ai.compute.start()
            with ai.device.transfer:
                image, label = image.to(device), label.to(device)
            with ai.compute.forward:
                for callback in callbacks:
                    callback.on_batch_start()
                if sleep >= 0:
                    emulate_compute(device, sleep)
                    continue

                with autocast(enabled=flags.amp, device_type="cuda"):
                    output = model(image)
                    loss_value = loss_fn(output, label)
                    loss_value /= flags.ga_steps
            with ai.compute.backward:
                if flags.amp:
                    scaler.scale(loss_value).backward()
                else:
                    loss_value.backward()

                if (iteration + 1) % flags.ga_steps == 0:
                    if flags.amp:
                        scaler.step(optimizer)
                        scaler.update()
                    else:
                        optimizer.step()

                    optimizer.zero_grad()
            with ai.comm.all_reduce:
                if not skip_reduce:
                    loss_value = (
                        reduce_tensor(loss_value, world_size).detach().cpu().numpy()
                    )
                    cumulative_loss.append(loss_value)
                else:
                    loss_value = 0.0
            ai.compute.stop()

        if flags.lr_decay_epochs:
            scheduler.step()
        if epoch == next_eval_at:
            next_eval_at += flags.evaluate_every
            del output

            eval_metrics = evaluate(
                flags, model, val_loader, loss_fn, score_fn, device, epoch
            )
            if skip_reduce:
                eval_metrics["train_loss"] = 0.15
            else:
                eval_metrics["train_loss"] = sum(cumulative_loss) / len(cumulative_loss)

            for callback in callbacks:
                callback.on_epoch_end(
                    epoch=epoch, metrics=eval_metrics, model=model, optimizer=optimizer
                )
            model.train()
            if eval_metrics["mean_dice"] >= flags.quality_threshold:
                is_successful = True
            elif eval_metrics["mean_dice"] < 1e-6:
                print("MODEL DIVERGED. ABORTING.")
                diverged = True

        if is_successful or diverged:
            break

    for callback in callbacks:
        callback.on_fit_end()
