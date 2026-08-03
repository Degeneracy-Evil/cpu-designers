"""Layered hash computation for source change detection.

Computes per-layer SHA256 hashes over project source files so that
stale sessions can be detected and incremental refreshes planned.

Layers:
- **rtl**:  src/rtl/**/*.sv + src/rtl/**/*.svh + Reference/**/*.xci
- **tb**:   src/tb/**/*.sv
- **src**:  src/program_source/**/*.{s,S,c,h,ld} + build.yaml + test_builder.py + rv2coe.py
- **coe**:  src/program_source/{test,app,boot}/**/*.{coe,hex}
- **fpga**: src/fpga/**/*.xdc + src/fpga/**/*.dcp + tools/vivado_core/tcl/**/*.tcl
"""
from __future__ import annotations

import hashlib
from pathlib import Path


class LayeredHash:
    """Compute per-layer SHA256 hashes for source change detection.

    Each layer covers a distinct set of source files.  The hash is the
    first 8 hex characters of the SHA256 digest computed over all files
    in the layer (read in sorted path order for determinism).

    Parameters
    ----------
    base_dir:
        Project root directory (the repo checkout root).
    """

    LAYERS: tuple[str, ...] = ("rtl", "tb", "src", "coe", "fpga")

    HASH_GLOBS: dict[str, list[str]] = {
        "rtl": [
            "src/rtl/**/*.sv",
            "src/rtl/**/*.svh",
            "Reference/**/*.xci",
            "config/vivado_config.yaml",
            "tools/vivado_core/**/*.py",
            "Reference/ddr3_sim/**/*.sv",
            "Reference/ddr3_sim/**/*.vh",
            "Reference/ddr3_sim/**/*.v",
        ],
        "tb": [
            "src/tb/**/*.sv",
        ],
        "src": [
            "src/program_source/**/*.s",
            "src/program_source/**/*.S",
            "src/program_source/**/*.c",
            "src/program_source/**/*.h",
            "src/program_source/**/*.ld",
            "src/program_source/build.yaml",
            "tools/test_builder.py",
            "tools/rv2coe.py",
        ],
        "coe": [
            "src/program_source/test/**/*.coe",
            "src/program_source/test/**/*.hex",
            "src/program_source/app/**/*.coe",
            "src/program_source/app/**/*.hex",
            "src/program_source/boot/**/*.coe",
            "src/program_source/boot/**/*.hex",
        ],
        "fpga": [
            "src/fpga/**/*.xdc",
            "src/fpga/**/*.dcp",
            "tools/vivado_core/tcl/**/*.tcl",
        ],
    }

    def __init__(self, base_dir: Path | str) -> None:
        self.base_dir = Path(base_dir).resolve()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def compute_current(self) -> dict[str, str]:
        """Compute hashes for all layers.

        Returns
        -------
        dict[str, str]
            Mapping ``{layer_name: hex_hash[:16]}``.
        """
        return {layer: self.compute_single_layer(layer) for layer in self.LAYERS}

    def compute_staleness(
        self, session_hashes: dict[str, str]
    ) -> dict[str, bool]:
        """Compare current hashes against a session's stored hashes.

        Parameters
        ----------
        session_hashes:
            Previously stored ``{layer: hash}`` mapping (from
            ``SessionMeta.hashes``).

        Returns
        -------
        dict[str, bool]
            ``{layer: is_stale}`` — ``True`` if the layer has changed
            or was not previously recorded.
        """
        current = self.compute_current()
        return {
            layer: current.get(layer, "") != session_hashes.get(layer, "")
            for layer in self.LAYERS
        }

    def compute_single_layer(self, layer: str) -> str:
        """Compute the hash for a single layer.

        Parameters
        ----------
        layer:
            One of :attr:`LAYERS`.

        Returns
        -------
        str
            First 8 hex characters of the SHA256 digest.

        Raises
        ------
        ValueError
            If *layer* is not a recognised layer name.
        """
        if layer not in self.HASH_GLOBS:
            raise ValueError(
                f"Unknown layer {layer!r}; expected one of {self.LAYERS}"
            )

        hasher = hashlib.sha256()
        patterns = self.HASH_GLOBS[layer]

        # Collect all matching files across all glob patterns for this layer.
        matched_files: list[Path] = []
        for pattern in patterns:
            matched_files.extend(self.base_dir.glob(pattern))

        # Sort for deterministic ordering.
        matched_files.sort()

        for fpath in matched_files:
            if not fpath.is_file():
                continue
            # Include the relative path in the hash so that file renames
            # are detected even if content is unchanged.
            rel = fpath.relative_to(self.base_dir)
            hasher.update(rel.as_posix().encode("utf-8"))
            hasher.update(b"\x00")  # separator
            # Read file content (binary-safe for .dcp etc.).
            hasher.update(fpath.read_bytes())

        return hasher.hexdigest()[:16]
