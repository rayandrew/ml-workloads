import socket
from typing import Any, Dict, Optional, Type, TypeVar, overload

import numpy as np


def remove_glob_syntax(path: str) -> str:
    """Remove glob syntax from a file path."""
    return path.replace("*", "").replace("?", "")


class Singleton(type):
    _instances: Dict[type, "Singleton"] = {}

    def __call__(cls, *args: Any, **kwargs: Any) -> Any:
        if cls not in cls._instances:
            cls._instances[cls] = super().__call__(*args, **kwargs)
        return cls._instances[cls]

    def instance(cls: Any, *args: Any, **kwargs: Any) -> Any:
        return cls(*args, **kwargs)

    def has(cls: Any) -> bool:
        return cls in cls._instances

    def reset(cls: Any) -> None:
        cls._instances = {}

    def remove(cls: Any) -> None:
        if cls in cls._instances:
            del cls._instances[cls]


def is_package_avail(name: str) -> bool:
    import importlib.util
    import sys

    if name in sys.modules:
        return True
    elif (spec := importlib.util.find_spec(name)) is not None:
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        if spec.loader:
            spec.loader.exec_module(module)
            return True
    return False


def find_free_network_port() -> int:
    """Finds a free port on localhost.

    It is useful in single-node training when we don't want to connect to a real main node but have to set the
    `MASTER_PORT` environment variable.

    """
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("", 0))
    port = s.getsockname()[1]
    s.close()
    return port


# https://stackoverflow.com/a/52872579
def is_port_in_use(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(("localhost", port)) == 0


def find_free_network_port_if_taken(port: Optional[int] = None) -> int:
    """Finds a free port on localhost if the given port is taken."""
    if port is None:
        return find_free_network_port()

    if is_port_in_use(port):
        return find_free_network_port()

    return port


def lc_machine_full_hostname(hostname: str):
    return f"{hostname}.llnl.gov"


cluster_name: Optional[str] = None


def get_cluster_name():
    global cluster_name
    if cluster_name is None:
        hostname = socket.gethostname()
        if "corona" in hostname:
            cluster_name = "corona"
        elif "tuolumne" in hostname:
            cluster_name = "tuolumne"
    return cluster_name


TBaseClass = TypeVar("TBaseClass")


@overload
def discover_cls_fqn(fqn: str, base_class: None = None) -> Optional[type]: ...


@overload
def discover_cls_fqn(
    fqn: str, base_class: Type[TBaseClass]
) -> Optional[Type[TBaseClass]]: ...


def discover_cls_fqn(
    fqn: str, base_class: Optional[Type[TBaseClass]] = None
) -> Optional[Type[TBaseClass]] | Optional[type]:
    """
    Discover a class by its fully qualified name.

    Args:
        fqn: Fully qualified name of the class (e.g., "module.submodule.ClassName")
        base_class: Optional base class to check inheritance against

    Returns:
        A concrete subclass of base_class if found, None otherwise.
        When base_class is provided, the returned class is guaranteed to be
        instantiable (not abstract) if it's a proper subclass.
    """
    import importlib
    import inspect

    classname = fqn.split(".")[-1]
    module_name = ".".join(fqn.split(".")[:-1])

    try:
        module = importlib.import_module(module_name)
    except ImportError:
        return None

    for class_name, obj in inspect.getmembers(module, inspect.isclass):
        if class_name == classname:
            if base_class is None:
                return obj  # type: ignore
            elif issubclass(obj, base_class):
                return obj  # type: ignore

    return None


def convert_numpy_to_scalar(obj) -> Any:
    """Recursively convert numpy types to Python scalars for YAML serialization"""

    if isinstance(obj, dict):
        return {key: convert_numpy_to_scalar(value) for key, value in obj.items()}
    elif isinstance(obj, list):
        return [convert_numpy_to_scalar(item) for item in obj]
    elif isinstance(obj, (np.integer, np.floating, np.ndarray)):
        return obj.item() if hasattr(obj, "item") else float(obj)
    elif isinstance(obj, np.bool_):
        return bool(obj)
    else:
        return obj
