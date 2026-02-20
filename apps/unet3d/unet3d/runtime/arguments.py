import argparse
import os
from typing import Any, Optional, overload

from src.args import Arguments, DynamicArgumentParser, GroupedArguments
from src.utils import Singleton
from src.logging import log0


class UNet3DArguments(Arguments, GroupedArguments):
    def get_section_name(self) -> str:
        return "UNet-3D"

    def get_section_description(self) -> Optional[str]:
        return "UNet-3D configuration parameters."

    def add_arguments(self, parser):
        parser.add_argument("--data_dir", dest="data_dir", required=True)
        parser.add_argument("--log_dir", dest="log_dir", type=str, default="/tmp")
        parser.add_argument(
            "--output_dir", dest="output_dir", type=str, default="./results"
        )
        parser.add_argument(
            "--save_ckpt_path", dest="save_ckpt_path", type=str, default=""
        )
        parser.add_argument(
            "--load_ckpt_path", dest="load_ckpt_path", type=str, default=""
        )
        parser.add_argument("--loader", dest="loader", default="pytorch", type=str)
        parser.add_argument(
            "--local_rank", default=os.environ.get("LOCAL_RANK", 0), type=int
        )
        parser.add_argument("--epochs", dest="epochs", type=int, default=1)
        parser.add_argument(
            "--quality_threshold", dest="quality_threshold", type=float, default=0.908
        )
        parser.add_argument("--ga_steps", dest="ga_steps", type=int, default=1)
        parser.add_argument("--warmup_steps", dest="warmup_steps", type=int, default=4)
        parser.add_argument("--batch_size", dest="batch_size", type=int, default=2)
        parser.add_argument(
            "--layout", dest="layout", type=str, choices=["NCDHW"], default="NCDHW"
        )
        parser.add_argument(
            "--input_shape", nargs="+", type=int, default=[128, 128, 128]
        )
        parser.add_argument(
            "--val_input_shape", nargs="+", type=int, default=[128, 128, 128]
        )
        parser.add_argument("--seed", dest="seed", default=-1, type=int)
        parser.add_argument("--num_workers", dest="num_workers", type=int, default=8)
        parser.add_argument(
            "--exec_mode",
            dest="exec_mode",
            choices=["train", "evaluate"],
            default="train",
        )
        parser.add_argument(
            "--benchmark", dest="benchmark", action="store_true", default=False
        )
        parser.add_argument("--amp", dest="amp", action="store_true", default=False)
        parser.add_argument(
            "--optimizer",
            dest="optimizer",
            default="sgd",
            choices=["sgd", "adam", "lamb"],
            type=str,
        )
        parser.add_argument(
            "--learning_rate", dest="learning_rate", type=float, default=1.0
        )
        parser.add_argument(
            "--init_learning_rate", dest="init_learning_rate", type=float, default=1e-4
        )
        parser.add_argument(
            "--lr_warmup_epochs", dest="lr_warmup_epochs", type=int, default=0
        )
        parser.add_argument("--lr_decay_epochs", nargs="+", type=int, default=[])
        parser.add_argument(
            "--lr_decay_factor", dest="lr_decay_factor", type=float, default=1.0
        )
        parser.add_argument("--lamb_betas", nargs="+", type=int, default=[0.9, 0.999])
        parser.add_argument("--momentum", dest="momentum", type=float, default=0.9)
        parser.add_argument(
            "--weight_decay", dest="weight_decay", type=float, default=0.0
        )
        parser.add_argument(
            "--evaluate_every",
            "--eval_every",
            dest="evaluate_every",
            type=int,
            default=None,
        )
        parser.add_argument(
            "--start_eval_at", dest="start_eval_at", type=int, default=None
        )
        parser.add_argument(
            "--verbose", "-v", dest="verbose", action="store_true", default=False
        )
        parser.add_argument(
            "--normalization",
            dest="normalization",
            type=str,
            choices=["instancenorm", "batchnorm"],
            default="instancenorm",
        )
        parser.add_argument(
            "--activation",
            dest="activation",
            type=str,
            choices=["relu", "leaky_relu"],
            default="relu",
        )
        parser.add_argument(
            "--oversampling", dest="oversampling", type=float, default=0.4
        )
        parser.add_argument("--sleep", dest="sleep", type=float, default=-1.0)
        parser.add_argument("--overlap", dest="overlap", type=float, default=0.5)
        parser.add_argument(
            "--include_background",
            dest="include_background",
            action="store_true",
            default=False,
        )
        parser.add_argument(
            "--cudnn_benchmark",
            dest="cudnn_benchmark",
            action="store_true",
            default=False,
        )
        parser.add_argument(
            "--cudnn_deterministic",
            dest="cudnn_deterministic",
            action="store_true",
            default=False,
        )
        parser.add_argument(
            "--max-training-step",
            type=int,
            default=-1,
            help="Maximum training steps (default: -1 for unlimited)",
        )


def create_parser():
    return (
        DynamicArgumentParser(description="UNet-3D")
        .add(UNet3DArguments())
        .create_parser()
    )


class Args(metaclass=Singleton):
    def __init__(self):
        if Singleton.has(Args):
            raise Exception(
                "Args is a singleton class and cannot be instantiated more than once."
            )
        self.parser: Optional[DynamicArgumentParser] = None
        self.args: Optional[argparse.Namespace] = None

    @staticmethod
    def get_default_parser() -> DynamicArgumentParser:
        return DynamicArgumentParser(description="UNet-3D").add(UNet3DArguments())

    @staticmethod
    def instance() -> "Args":
        instance = Singleton.instance(Args)
        return instance

    @staticmethod
    def get_args() -> argparse.Namespace:
        if Args.instance().args is None:
            raise RuntimeError(
                "Args have not been parsed yet. Call Args.parse() first."
            )
        return Args.instance().args  # type: ignore[return-value]

    @overload
    @staticmethod
    def get(key: str) -> Any: ...

    @overload
    @staticmethod
    def get() -> argparse.Namespace: ...

    @staticmethod
    def get(key: Optional[str] = None) -> argparse.Namespace | Any:
        args = Args.get_args()
        if key is not None:
            if not hasattr(args, key):
                raise KeyError(f"Argument '{key}' not found.")
            return getattr(args, key)
        return args

    @staticmethod
    def parse(parser: Optional[DynamicArgumentParser] = None) -> argparse.Namespace:
        instance = Args.instance()
        if parser is not None:
            instance.parser = parser
        else:
            instance.parser = Args.get_default_parser()
        instance.args = instance.parser.create_parser()
        for key, value in vars(instance.args).items():
            setattr(instance, key, value)
        return instance.args

    @staticmethod
    def print_args() -> None:
        args = Args.get()
        log0("Arguments:")
        for arg, value in vars(args).items():
            log0(f"  {arg}: {value}")

    @staticmethod
    def as_dict() -> dict:
        return vars(Args.get())

    @staticmethod
    def as_namespace() -> argparse.Namespace:
        return Args.get()
