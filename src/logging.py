import inspect
import logging
import os
import platform
import sys
import time
import warnings
from functools import wraps
from typing import Any, Callable, Union

import torch

from strenum import StrEnum

from src.mpi_utils import MPIUtils

logger = logging.getLogger(__name__)


# https://medium.com/@ryan_forrester_/adding-color-to-python-terminal-output-a-complete-guide-147fcb1c335f
def _enable_windows_color():
    """Enable color support on Windows"""
    try:
        import ctypes

        kernel32 = ctypes.windll.kernel32
        kernel32.SetConsoleMode(kernel32.GetStdHandle(-11), 7)
        return True
    except Exception:
        return False


# https://medium.com/@ryan_forrester_/adding-color-to-python-terminal-output-a-complete-guide-147fcb1c335f
def _check_color_supports():
    """Check if the current terminal supports colors"""
    # Force colors if FORCE_COLOR env variable is set
    if os.getenv("FORCE_COLOR"):
        return True

    # Check platform-specific support
    if platform.system() == "Windows":
        return _enable_windows_color()

    # Most Unix-like systems support colors
    return os.getenv("TERM") not in ("dumb", "")


color_supported = _check_color_supports()


# https://stackoverflow.com/a/55612356
class FormatterNanosecond(logging.Formatter):
    default_nsec_format = "%s,%09d"

    def formatTime(self, record, datefmt=None):
        if datefmt is not None:
            return super().formatTime(record, datefmt)
        ct = self.converter(record.created_ns / 1e9)
        t = time.strftime(self.default_time_format, ct)
        s = self.default_nsec_format % (
            t,
            record.created_ns - (record.created_ns // 10**9) * 10**9,
        )
        return s


class ColoredFormatter(logging.Formatter):
    _green = "\x1b[32;20m"
    _purple = "\x1b[35;20m"
    _yellow = "\x1b[33;20m"
    _red = "\x1b[31;20m"
    _bold_red = "\x1b[31;1m"
    _reset = "\x1b[0m"
    _blue = "\x1b[34;20m"
    _magenta = "\x1b[35;20m"
    _cyan = "\x1b[36;20m"
    _white = "\x1b[37;20m"
    _orange = "\x1b[38;5;208m"
    _prefix_format = "%(levelname).1s"
    _time_format = "%(asctime)s"

    LEVEL_FMT = {
        logging.DEBUG: _cyan + _prefix_format + _reset,
        logging.INFO: _green + _prefix_format + _reset,
        logging.WARNING: _yellow + _prefix_format + _reset,
        logging.ERROR: _red + _prefix_format + _reset,
        logging.CRITICAL: _bold_red + _prefix_format + _reset,
    }

    @staticmethod
    def process_format(fmt: str, levelno) -> str:
        fmt = fmt.replace("^lvl^", ColoredFormatter.LEVEL_FMT.get(levelno))
        fmt = fmt.replace("^time^", ColoredFormatter._time_format)
        if not color_supported:
            fmt = fmt.replace("^green^", "")
            fmt = fmt.replace("^purple^", "")
            fmt = fmt.replace("^yellow^", "")
            fmt = fmt.replace("^red^", "")
            fmt = fmt.replace("^bold_red^", "")
            fmt = fmt.replace("^reset^", "")
            fmt = fmt.replace("^blue^", "")
            fmt = fmt.replace("^magenta^", "")
            fmt = fmt.replace("^cyan^", "")
            fmt = fmt.replace("^white^", "")
            return fmt
        # to enable color, user should set following format
        # ^color^ [%(levelname).1s] ^reset^ %(asctime)s - %(message)s
        fmt = fmt.replace("^green^", ColoredFormatter._green)
        fmt = fmt.replace("^purple^", ColoredFormatter._purple)
        fmt = fmt.replace("^yellow^", ColoredFormatter._yellow)
        fmt = fmt.replace("^red^", ColoredFormatter._red)
        fmt = fmt.replace("^bold_red^", ColoredFormatter._bold_red)
        fmt = fmt.replace("^reset^", ColoredFormatter._reset)
        fmt = fmt.replace("^blue^", ColoredFormatter._blue)
        fmt = fmt.replace("^magenta^", ColoredFormatter._magenta)
        fmt = fmt.replace("^cyan^", ColoredFormatter._cyan)
        fmt = fmt.replace("^white^", ColoredFormatter._white)
        return fmt

    def format(self, record):
        # log_fmt = self.LEVEL_FMT.get(record.levelno)
        # log_fmt += self._green + self._time_format + self._reset + self._fmt
        log_fmt = self.process_format(fmt=self._fmt, levelno=record.levelno)
        formatter = FormatterNanosecond(log_fmt)
        return formatter.format(record)


# https://stackoverflow.com/a/55612356
class LogRecordNanosecond(logging.LogRecord):
    def __init__(self, *args, **kwargs):
        self.created_ns = time.time_ns()  # Fetch precise timestamp
        super().__init__(*args, **kwargs)


logging.setLogRecordFactory(LogRecordNanosecond)


class LogLevel(StrEnum):
    DEBUG = "DEBUG"
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"
    CRITICAL = "CRITICAL"


def loglevel_to_logging(level: LogLevel) -> int:
    mapping = {
        LogLevel.DEBUG: logging.DEBUG,
        LogLevel.INFO: logging.INFO,
        LogLevel.WARNING: logging.WARNING,
        LogLevel.ERROR: logging.ERROR,
        LogLevel.CRITICAL: logging.CRITICAL,
    }
    return mapping.get(level, logging.INFO)


def configure_logging(
    log_level: LogLevel = LogLevel.INFO, output_dir: str | None = None
):
    logfile_path = None
    if output_dir:
        logfile_path = os.path.join(output_dir, "runtime.log")

    log_level_config = log_level
    log_level = loglevel_to_logging(log_level_config)

    fmt = "[%(levelname).1s][%(asctime)s] %(message)s"
    handlers = []

    stdout_handler = logging.StreamHandler(stream=sys.stdout)
    stdout_handler.setLevel(log_level)
    # stdout_handler.setFormatter(ColoredFormatter("%(message)s [%(pathname)s:%(lineno)d"))
    # stdout_handler.setFormatter(ColoredFormatter("[^lvl^][^blue^^time^^reset^] ^yellow^%(message)s^reset^ ^purple^[%(pathname)s:%(lineno)d]^reset^"))
    stdout_handler.setFormatter(
        ColoredFormatter("[^lvl^][^blue^^time^^reset^] ^yellow^%(message)s^reset^")
    )

    handlers.append(stdout_handler)

    if logfile_path:
        # fmt = "[%(levelname).1s][%(asctime)s] %(message)s [%(pathname)s:%(lineno)d]"
        file_handler = logging.FileHandler(logfile_path, mode="a", encoding="utf-8")
        file_handler.setLevel(logging.DEBUG)
        file_handler.setFormatter(FormatterNanosecond(fmt))
        handlers.append(file_handler)

    logging.basicConfig(
        level=log_level,
        force=True,
        handlers=handlers,
        format=fmt,
    )


# Copied from arrgen
# https://github.com/stockeh/arrgen/blob/e3e94184176fd1f84373993860212c488714efde/src/arrgen/utils/io.py#L18

_logger_cache = {}
_logger_modes = {"info", "debug", "warning", "error", "critical"}


def _s(x):
    if isinstance(x, torch.Tensor):
        # don’t materialize values; just metadata
        if x.ndim == 0:
            return f"Tensor0D(dtype={x.dtype}, device={x.device})"
        return f"Tensor(shape={tuple(x.shape)}, dtype={x.dtype}, device={x.device})"
    return x


def log(*args, mode: str = "info", **kwargs):
    if mode not in _logger_modes:
        raise ValueError(f"Invalid mode '{mode}'. Supported modes are: {_logger_modes}")

    frame = inspect.currentframe().f_back
    try:
        code = frame.f_code
        key = (code.co_filename, code.co_name)

        if key not in _logger_cache:
            filename = os.path.splitext(os.path.basename(code.co_filename))[0]
            _logger_cache[key] = logging.getLogger(f"{filename}.{code.co_name}")

        logger = _logger_cache[key]
        log_function = getattr(logger, mode)
        processed_args = [_s(arg) for arg in args]
        processed_kwargs = {k: _s(v) for k, v in kwargs.items()}
        log_function(*processed_args, **processed_kwargs)

    finally:
        del frame


def log0(*args, global_zero: bool = True, mode: str = "info", **kwargs):
    """
    Logs messages for rank 0 only, with the caller's context.

    Parameters:
    - args: Message arguments to log.
    - mode: Logging level/mode ('info', 'debug', 'warning', 'error', 'critical').

    Example:
        log0("This is a test message", mode="debug")
    """

    should_log = False
    if global_zero:
        should_log = MPIUtils.global_zero()
    else:
        should_log = MPIUtils.rank() == 0

    if should_log:
        log(*args, mode=mode, **kwargs)


def print0(*args, global_zero: bool = True, **kwargs):
    should_log = False
    if global_zero:
        should_log = MPIUtils.global_zero()
    else:
        should_log = MPIUtils.rank() == 0

    if should_log:
        print(*args, **kwargs)


def warn0(
    message: Union[str, Warning],
    global_zero: bool = True,
    stacklevel: int = 2,
    **kwargs: Any,
):
    should_log = False
    if global_zero:
        should_log = MPIUtils.global_zero()
    else:
        should_log = MPIUtils.rank() == 0

    if not should_log:
        return

    if isinstance(message, str):
        kwargs["stacklevel"] = stacklevel
        log0(message, **kwargs, mode="warning")
    else:
        warnings.warn(message, stacklevel=stacklevel, **kwargs)


def suppress_logging():
    logging.getLogger("lightning.fabric").setLevel(logging.ERROR)
    logging.getLogger("lightning.pytorch").setLevel(logging.ERROR)
    logging.getLogger("lightning.fabric.utilities.rank_zero").setLevel(logging.ERROR)
    logging.getLogger("rank_zero").setLevel(logging.ERROR)


def timeit(func: Callable, rank_zero_only: bool = True) -> Callable:
    @wraps(func)
    def wrapper(*args, **kwargs):
        t0 = time.perf_counter()
        result = func(*args, **kwargs)
        dt = time.perf_counter() - t0
        if rank_zero_only:
            log0(f"runtime/{func.__qualname__} took: {dt=:.4f}s")
        else:
            logger.info(f"runtime/{func.__qualname__} took: {dt=:.4f}s")
        return result

    return wrapper


__all__ = [
    "ColoredFormatter",
    "FormatterNanosecond",
    "configure_logging",
    "LogLevel",
    "log",
    "log0",
    "print0",
    "warn0",
    "suppress_logging",
    "timeit",
]
