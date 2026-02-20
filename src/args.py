import argparse
import sys
from abc import ABC, abstractmethod
from enum import Enum
from typing import Any, Generic, List, Optional, Type, TypeVar, Union

Parser = Union[argparse.ArgumentParser, argparse._ArgumentGroup]
T = TypeVar("T")


class Arguments(ABC):
    @abstractmethod
    def add_arguments(self, parser: Parser):
        pass


class ConditionalArguments(ABC, Generic[T]):
    @abstractmethod
    def add_arguments(self, parser: Parser, type_value: T):
        pass

    @abstractmethod
    def get_type_class(self) -> Union[Type[T], List[str]]:
        pass

    @abstractmethod
    def get_type_arg_name(self) -> str:
        pass

    def get_type_choices(self) -> List[str]:
        type_class = self.get_type_class()

        if isinstance(type_class, type) and issubclass(type_class, Enum):
            return [e.value for e in type_class]
        elif isinstance(type_class, list):
            return type_class
        else:
            raise ValueError(f"Unsupported type class: {type_class}")

    def parse_type_value(self, value: str) -> T:
        type_class = self.get_type_class()

        if isinstance(type_class, type) and issubclass(type_class, Enum):
            return type_class(value)  # type: ignore
        else:
            return value  # type: ignore

    def get_default_section_name(self) -> str:
        return f"{self.get_type_arg_name().replace('_', ' ').title()} Options"


class GroupedArguments:
    @abstractmethod
    def get_section_name(self) -> str:
        pass

    def get_section_description(self) -> Optional[str]:
        return None


class DynamicArgumentParser:
    def __init__(
        self,
        conditional_args: Optional[List[ConditionalArguments[Any]]] = None,
        common_args: Optional[List[Arguments]] = None,
        description: str = "Dynamic argument parser",
    ):
        self.conditional_args = conditional_args or []
        self.common_args = common_args or []
        self.description = description

    def add_conditional(
        self, args: ConditionalArguments[Any]
    ) -> "DynamicArgumentParser":
        self.conditional_args.append(args)
        return self

    def add_common(self, args: Arguments) -> "DynamicArgumentParser":
        self.common_args.append(args)
        return self

    def add(
        self, args: Union[Arguments, ConditionalArguments[Any]]
    ) -> "DynamicArgumentParser":
        if isinstance(args, ConditionalArguments):
            self.conditional_args.append(args)
        else:
            self.common_args.append(args)
        return self

    def create_parser(self) -> argparse.Namespace:
        if self.conditional_args:
            return self._create_conditional_parser()
        else:
            return self._create_simple_parser()

    def _add_common_arguments(self, parser: argparse.ArgumentParser, args: Arguments):
        if isinstance(args, GroupedArguments):
            arg_group = parser.add_argument_group(
                args.get_section_name(), args.get_section_description()
            )
            args.add_arguments(arg_group)
        else:
            args.add_arguments(parser)

    def _add_conditional_arguments(
        self,
        parser: argparse.ArgumentParser,
        args: ConditionalArguments[Any],
        type_value: Any,
    ):
        if isinstance(args, GroupedArguments):
            arg_group = parser.add_argument_group(
                args.get_section_name(), args.get_section_description()
            )
            args.add_arguments(arg_group, type_value)
        else:
            args.add_arguments(parser, type_value)

    def _create_conditional_parser(self) -> argparse.Namespace:
        has_help = "--help" in sys.argv or "-h" in sys.argv

        type_args_provided = True
        for args in self.conditional_args:
            arg_name = f"--{args.get_type_arg_name().replace('_', '-')}"
            if arg_name not in sys.argv:
                type_args_provided = False
                break

        if has_help and not type_args_provided:
            help_parser = argparse.ArgumentParser(
                description=f"{self.description}\n\nNote: Additional options will be available based on your type selections.",
                formatter_class=argparse.RawDescriptionHelpFormatter,
            )

            type_group = help_parser.add_argument_group(
                "Type Selection",
                "Choose the types that will determine available options",
            )

            for args in self.conditional_args:
                arg_name = f"--{args.get_type_arg_name().replace('_', '-')}"
                type_choices = args.get_type_choices()
                type_group.add_argument(
                    arg_name,
                    choices=type_choices,
                    required=True,
                    help=f"Choose {args.get_type_arg_name().replace('_', ' ')} from {type_choices}",
                )

            for args in self.common_args:
                self._add_common_arguments(help_parser, args)

            print("Run with specific types to see all available options:\n")

            example_args = []
            for args in self.conditional_args:
                type_choices = args.get_type_choices()
                example_args.append(
                    f"--{args.get_type_arg_name().replace('_', '-')} {type_choices[0]}"
                )

            print(f"Example: {sys.argv[0]} {' '.join(example_args)} --help\n")

            help_parser.print_help()
            sys.exit(0)

        pre_parser = argparse.ArgumentParser(add_help=False)

        type_group = pre_parser.add_argument_group(
            "Type Selection", "Choose the types that will determine available options"
        )

        for args in self.conditional_args:
            arg_name = f"--{args.get_type_arg_name().replace('_', '-')}"
            type_group.add_argument(
                arg_name,
                choices=args.get_type_choices(),
                required=True,
                help=f"Choose {args.get_type_arg_name().replace('_', ' ')}",
            )

        pre_args, _ = pre_parser.parse_known_args()

        parser = argparse.ArgumentParser(
            parents=[pre_parser],
            description=self.description,
            formatter_class=argparse.RawDescriptionHelpFormatter,
        )

        for args in self.common_args:
            self._add_common_arguments(parser, args)

        for args in self.conditional_args:
            type_value_str = getattr(pre_args, args.get_type_arg_name())
            type_value = args.parse_type_value(type_value_str)
            self._add_conditional_arguments(parser, args, type_value)

        return parser.parse_args()

    def _create_simple_parser(self) -> argparse.Namespace:
        parser = argparse.ArgumentParser(
            description=self.description,
            formatter_class=argparse.RawDescriptionHelpFormatter,
        )

        # Add all common arguments (no type_value)
        for args in self.common_args:
            self._add_common_arguments(parser, args)

        return parser.parse_args()
