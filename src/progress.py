import statistics
import time
from collections import deque
from datetime import datetime, timedelta
from typing import Any, Callable, Optional, Dict

PrintFn = Callable[..., None]


class ProgressTracker:
    def __init__(
        self,
        print_function: Optional[PrintFn] = None,
        print_every_n: int = 50,
        max_batch_times: int = 100,
        smoothing: float = 0.3,
    ):
        self.print_fn = print_function or print
        self.print_every_n = print_every_n
        self.smoothing = smoothing

        t0 = time.perf_counter()
        self.training_start_time = t0
        self.epoch_start_time = t0
        self._last_batch_time = None

        self.batch_times = deque(maxlen=max_batch_times)
        self.ema_time_per_batch = None  # EMA of time per batch (sec)

        self.current_epoch = 0
        self.total_epochs = 0
        self.current_batch = 0
        self.total_batches = 0

        self._epoch_time_ema = None  # EMA of epoch durations (sec)

    def _format_time(self, seconds: Optional[float]) -> str:
        if seconds is None or seconds < 0:
            return "?"
        s = int(seconds + 0.5)
        if s < 60:
            return f"{s:d}s"
        m, s = divmod(s, 60)
        if m < 60:
            return f"{m}m {s:02d}s"
        h, m = divmod(m, 60)
        return f"{h}h {m:02d}m"

    def _calculate_eta(self, current_n: int, total_n: int, elapsed_time: float):
        if elapsed_time <= 0 or current_n <= 0:
            return None, "calculating..."

        rates = []

        # EMA-based recent rate
        if self.ema_time_per_batch and self.ema_time_per_batch > 0:
            rates.append(1.0 / self.ema_time_per_batch)

        # Robust recent median over last N batch times
        if len(self.batch_times) >= 3:
            recent = list(self.batch_times)[-min(50, len(self.batch_times)) :]
            try:
                t_med = statistics.median(recent)
            except statistics.StatisticsError:
                t_med = sum(recent) / max(1, len(recent))
            if t_med > 0:
                rates.append(1.0 / t_med)

        # Overall average since epoch start
        overall_rate = current_n / elapsed_time if elapsed_time > 0 else 0.0
        if overall_rate > 0:
            rates.append(overall_rate)

        if not rates:
            return None, "calculating..."

        if self.ema_time_per_batch and self.ema_time_per_batch > 0 and len(rates) > 1:
            final_rate = 0.7 * rates[0] + 0.3 * statistics.mean(rates[1:])
        else:
            final_rate = statistics.median(rates)

        remaining = max(0, total_n - current_n)
        eta_seconds = remaining / final_rate if final_rate > 0 else None
        return final_rate, (self._format_time(eta_seconds) if eta_seconds else "calculating...")

    def _calculate_total_training_eta(self) -> str:
        completed = self.current_epoch * self.total_batches + self.current_batch
        total = self.total_epochs * self.total_batches
        if completed <= 0 or total <= 0:
            return "calculating..."

        elapsed_total = time.perf_counter() - self.training_start_time
        avg_time_per_item = elapsed_total / completed
        remaining_items = max(0, total - completed)
        return self._format_time(remaining_items * avg_time_per_item)

    def start_training(self, total_epochs: int):
        self.training_start_time = time.perf_counter()
        self.total_epochs = total_epochs
        self._epoch_time_ema = None
        self.print_fn(f"Training started at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        self.print_fn(f"Total epochs: {total_epochs}")

    def start_epoch(self, epoch: int, total_batches: int):
        self.current_epoch = epoch
        self.total_batches = total_batches
        self.current_batch = 0
        self.epoch_start_time = time.perf_counter()
        self.batch_times.clear()
        self._last_batch_time = time.perf_counter()
        self.ema_time_per_batch = None  # reset epoch-local EMA

        self.print_fn(f"{'=' * 60}")
        self.print_fn(f"STARTING EPOCH {epoch + 1}/{self.total_epochs}")
        self.print_fn(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        self.print_fn(f"Batches in epoch: {total_batches}")
        self.print_fn(f"{'=' * 60}")

    def update_batch(self, batch_idx: int, metrics: Optional[Dict[Any, Any]] = None):
        now = time.perf_counter()
        self.current_batch = batch_idx + 1

        if self._last_batch_time is not None:
            dt = now - self._last_batch_time
            if dt > 0:
                self.batch_times.append(dt)
                a = self.smoothing
                self.ema_time_per_batch = (
                    dt
                    if self.ema_time_per_batch is None
                    else ((1 - a) * self.ema_time_per_batch + a * dt)
                )
        self._last_batch_time = now

        if batch_idx % self.print_every_n == 0 or batch_idx == self.total_batches - 1:
            progress = (batch_idx + 1) / self.total_batches * 100
            bar_len = 30
            filled = int(bar_len * progress / 100)
            bar = "█" * filled + "-" * (bar_len - filled)

            elapsed = now - self.epoch_start_time
            epoch_rate, epoch_eta = self._calculate_eta(batch_idx + 1, self.total_batches, elapsed)

            if epoch_rate is not None:
                if epoch_rate >= 10:
                    rate_str = f"{epoch_rate:.0f} batch/sec"
                elif epoch_rate >= 1:
                    rate_str = f"{epoch_rate:.1f} batch/sec"
                else:
                    rate_str = f"{1.0 / epoch_rate:.1f}s/batch"
            else:
                rate_str = "? batch/sec"

            # For single-epoch runs, Total ETA should mirror Epoch ETA
            if self.total_epochs <= 1:
                total_eta = epoch_eta
            else:
                total_eta = self._calculate_total_training_eta()

            self.print_fn(
                f"TRAIN: [{bar}] {batch_idx + 1:5d}/{self.total_batches:5d} "
                f"({progress:5.1f}%) | {rate_str}"
            )
            self.print_fn(
                f"       Elapsed: {self._format_time(elapsed)} | "
                f"Epoch ETA: {epoch_eta} | Total ETA: {total_eta}"
            )
            if metrics:
                metric_str = " | ".join([f"{k}: {v:.4f}" for k, v in metrics.items()])
                self.print_fn(f"       Metrics: {metric_str}")

    def end_epoch(self, final_metrics: Optional[Dict[Any, Any]] = None):
        epoch_time = time.perf_counter() - self.epoch_start_time
        total_elapsed = time.perf_counter() - self.training_start_time

        a = self.smoothing
        self._epoch_time_ema = (
            epoch_time
            if self._epoch_time_ema is None
            else ((1 - a) * self._epoch_time_ema + a * epoch_time)
        )

        remaining_epochs = self.total_epochs - (self.current_epoch + 1)
        remaining_time = max(0, remaining_epochs) * self._epoch_time_ema
        remaining_str = (
            f" | Remaining: {self._format_time(remaining_time)}" if remaining_epochs > 0 else ""
        )
        completion_str = (
            f"Estimated completion: {(datetime.now() + timedelta(seconds=remaining_time)).strftime('%Y-%m-%d %H:%M:%S')}"
            if remaining_epochs > 0
            else ""
        )

        self.print_fn(f"EPOCH {self.current_epoch + 1} COMPLETED")
        self.print_fn(
            f"Epoch time: {self._format_time(epoch_time)} | "
            f"Total elapsed: {self._format_time(total_elapsed)}{remaining_str}"
        )
        if completion_str:
            self.print_fn(completion_str)

        if final_metrics:
            self.print_fn("EPOCH METRICS:")
            for k, v in final_metrics.items():
                self.print_fn(f"  {k}: {v:.6f}")

        self.print_fn(f"{'=' * 60}")

    def end_training(self):
        total_time = time.perf_counter() - self.training_start_time
        self.print_fn("TRAINING COMPLETED")
        self.print_fn(f"Total training time: {self._format_time(total_time)}")
        self.print_fn(f"Completed at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")