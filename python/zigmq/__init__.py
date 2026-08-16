"""Python bridge for the pure-Zig zigmq core.

The package intentionally uses ctypes rather than a C extension. Build the
shared library with `zig build`, then set ZIGMQ_LIBRARY when it is outside the
standard repository layout.
"""

from __future__ import annotations

import ctypes
import ctypes.util
import os
from pathlib import Path


class ZigmqCore:
    """Thin Python wrapper around the exported Zig functions."""

    def __init__(self, library: str | os.PathLike[str] | None = None) -> None:
        path = self._find_library(library)
        self._lib = ctypes.CDLL(str(path))
        self._lib.zigmq_version.argtypes = []
        self._lib.zigmq_version.restype = ctypes.c_char_p
        self._lib.zigmq_validate_subject.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_bool]
        self._lib.zigmq_validate_subject.restype = ctypes.c_bool
        self._lib.zigmq_subject_matches.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t]
        self._lib.zigmq_subject_matches.restype = ctypes.c_bool
        self._lib.zigmq_fnv1a64.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
        self._lib.zigmq_fnv1a64.restype = ctypes.c_uint64
        self._lib.zigmq_pub_frame_size.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_size_t]
        self._lib.zigmq_pub_frame_size.restype = ctypes.c_size_t
        self._lib.zigmq_encode_pub_frame.argtypes = [
            ctypes.c_void_p,
            ctypes.c_size_t,
            ctypes.c_void_p,
            ctypes.c_size_t,
            ctypes.c_void_p,
            ctypes.c_size_t,
        ]
        self._lib.zigmq_encode_pub_frame.restype = ctypes.c_size_t

    @staticmethod
    def _find_library(library: str | os.PathLike[str] | None) -> Path | str:
        if library is not None:
            return Path(library)
        environment = os.environ.get("ZIGMQ_LIBRARY")
        if environment:
            return Path(environment)
        root = Path(__file__).resolve().parents[2]
        candidates = [
            root / "zig-out" / "lib" / "libzigmq_core.so",
            root / "zig-out" / "lib" / "libzigmq_core.dylib",
            root / "zig-out" / "bin" / "zigmq_core.dll",
        ]
        for candidate in candidates:
            if candidate.exists():
                return candidate
        discovered = ctypes.util.find_library("zigmq_core")
        if discovered:
            return discovered
        raise FileNotFoundError("libzigmq_core not found; run `zig build` or set ZIGMQ_LIBRARY")

    @property
    def version(self) -> str:
        return self._lib.zigmq_version().decode("utf-8")

    def validate_subject(self, subject: str | bytes, *, allow_wildcards: bool = False) -> bool:
        data = subject.encode() if isinstance(subject, str) else subject
        return bool(self._lib.zigmq_validate_subject(data, len(data), allow_wildcards))

    def matches(self, pattern: str | bytes, subject: str | bytes) -> bool:
        pattern_bytes = pattern.encode() if isinstance(pattern, str) else pattern
        subject_bytes = subject.encode() if isinstance(subject, str) else subject
        return bool(self._lib.zigmq_subject_matches(pattern_bytes, len(pattern_bytes), subject_bytes, len(subject_bytes)))

    def hash64(self, data: str | bytes) -> int:
        raw = data.encode() if isinstance(data, str) else data
        return int(self._lib.zigmq_fnv1a64(raw, len(raw)))

    def encode_pub(self, subject: str | bytes, payload: str | bytes) -> bytes:
        subject_bytes = subject.encode() if isinstance(subject, str) else subject
        payload_bytes = payload.encode() if isinstance(payload, str) else payload
        size = int(self._lib.zigmq_pub_frame_size(subject_bytes, len(subject_bytes), len(payload_bytes)))
        if size == 0:
            raise ValueError("invalid subject or payload too large")
        output = ctypes.create_string_buffer(size)
        written = int(
            self._lib.zigmq_encode_pub_frame(
                subject_bytes,
                len(subject_bytes),
                payload_bytes,
                len(payload_bytes),
                output,
                size,
            )
        )
        if written != size:
            raise RuntimeError("Zig frame encoder returned an unexpected size")
        return output.raw[:written]


__all__ = ["ZigmqCore"]
