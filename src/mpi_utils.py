import os
import socket
from typing import Any, Optional

from mpi4py import MPI

from src.utils import (
    Singleton,
    find_free_network_port_if_taken,
    lc_machine_full_hostname,
)


class MPIUtils(metaclass=Singleton):
    def __init__(self):
        if Singleton.has(MPIUtils):
            raise RuntimeError(
                "MPIUtils is a singleton class and cannot be instantiated more than once."
            )

        self._rank: int = 0
        self._local_rank: int = 0
        self._size: int = 1
        self._num_nodes: int = 1
        self._ppn: int = 1
        self._is_initialized: bool = False
        self._comm_world: Optional[MPI.Comm] = None
        self._comm_local: Optional[MPI.Comm] = None

    @staticmethod
    def instance(*args: Any, **kwargs: Any) -> "MPIUtils":
        instance = Singleton.instance(MPIUtils, *args, **kwargs)
        return instance

    def _initialize(self):
        if self._is_initialized:
            return

        if not MPI.Is_initialized():
            MPI.Init()

        self._comm_world = MPI.COMM_WORLD
        self._comm_local = MPI.COMM_WORLD.Split_type(MPI.COMM_TYPE_SHARED)
        self._rank = self._comm_world.Get_rank()
        self._size = self._comm_world.Get_size()
        self._local_rank = self._comm_local.Get_rank()
        self._ppn = self._comm_local.Get_size()
        self._num_nodes = self._size // self._ppn
        self._is_initialized = True

    @staticmethod
    def is_initialized() -> bool:
        return MPIUtils.instance()._is_initialized

    @staticmethod
    def initialize() -> "MPIUtils":
        instance = MPIUtils.instance()
        instance._initialize()
        return instance

    @staticmethod
    def rank() -> int:
        return MPIUtils.instance()._rank

    @staticmethod
    def local_rank() -> int:
        return MPIUtils.instance()._local_rank

    @staticmethod
    def size() -> int:
        return MPIUtils.instance()._size

    @staticmethod
    def world_size() -> int:
        return MPIUtils.instance()._size

    @staticmethod
    def global_zero() -> bool:
        return MPIUtils.instance()._rank == 0 and MPIUtils.instance()._local_rank == 0

    @staticmethod
    def local_zero() -> bool:
        return MPIUtils.instance()._local_rank == 0

    @staticmethod
    def num_nodes() -> int:
        return MPIUtils.instance()._num_nodes

    @staticmethod
    def ppn() -> int:
        return MPIUtils.instance()._ppn

    @staticmethod
    def comm_world() -> MPI.Comm:
        assert MPIUtils.is_initialized(), (
            "MPIUtils must be initialized before accessing the world communicator."
        )
        comm = MPIUtils.instance()._comm_world
        if not comm:
            raise ValueError("World communicator is not initialized.")
        return comm

    @staticmethod
    def comm_local() -> MPI.Comm:
        assert MPIUtils.is_initialized(), (
            "MPIUtils must be initialized before accessing the local communicator."
        )
        comm = MPIUtils.instance()._comm_local
        if not comm:
            raise ValueError("Local communicator is not initialized.")
        return comm

    @staticmethod
    def finalize():
        instance = MPIUtils.instance()
        if instance._is_initialized:
            if MPI.Is_initialized():
                MPI.Finalize()
        instance._is_initialized = False
        instance._comm_world = None
        instance._comm_local = None
        Singleton.remove(MPIUtils)

    @staticmethod
    def num_devices() -> int:
        assert MPIUtils.is_initialized(), (
            "MPIUtils must be initialized before accessing number of devices."
        )
        return MPIUtils.instance()._ppn

    @staticmethod
    def barrier():
        MPIUtils.comm_world().barrier()


def get_rank():
    if not MPIUtils.is_initialized():
        MPIUtils.initialize()
    return MPIUtils.rank()


def get_local_rank():
    if not MPIUtils.is_initialized():
        MPIUtils.initialize()
    return MPIUtils.local_rank()


def get_world_size():
    if not MPIUtils.is_initialized():
        MPIUtils.initialize()
    return MPIUtils.size()


def get_hostname() -> str:
    """Gets the hostname of the current machine."""
    return socket.gethostname()


def get_master_addr_and_port(
    port: Optional[int] = None, lc_machine: bool = True, set_env: bool = True
) -> tuple[str, int]:
    """Gets the master address and port for distributed training."""
    if MPIUtils.is_initialized():
        if MPIUtils.rank() == 0:
            hostname = get_hostname()
            if lc_machine:
                hostname = lc_machine_full_hostname(hostname)
            port = find_free_network_port_if_taken(port)
        else:
            hostname = None
            port = None
        hostname = MPIUtils.comm_world().bcast(hostname, root=0)
        port = MPIUtils.comm_world().bcast(port, root=0)
        if set_env:
            os.environ["MASTER_ADDR"] = hostname
            os.environ["MASTER_PORT"] = str(port)
    else:
        hostname = get_hostname()
        port = find_free_network_port_if_taken(port)
    if not port:
        raise ValueError("Failed to find a free port.")
    return hostname, port


__all__ = ["MPIUtils", "get_rank", "get_local_rank", "get_world_size"]
