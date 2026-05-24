"""Synchronisation policy: preflight checks and refresh planning.

Determines whether a session is stale relative to the current source
files and, if so, what refresh steps are needed before an operation
can proceed.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from .hash import LayeredHash
from .session import Session
from .tasks import TaskConfig


# ---------------------------------------------------------------------------
# Result data classes
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class PreflightResult:
    """Outcome of a preflight staleness check.

    Attributes
    ----------
    ok:
        ``True`` if the operation can proceed without a mandatory
        refresh.
    reason:
        Human-readable explanation when *ok* is ``False``.
    fix:
        Suggested action to resolve the issue.
    severity:
        One of ``"ok"``, ``"warning"``, ``"error"``.
    stale_layers:
        Layers that have changed since the session was last
        created/refreshed.
    """

    ok: bool
    reason: str = ""
    fix: str = ""
    severity: str = "ok"
    stale_layers: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class RefreshPlan:
    """Planned refresh steps derived from staleness information.

    Attributes
    ----------
    full:
        ``True`` if a full rebuild is required (RTL layer changed).
    layers:
        Which layers need to be refreshed.
    tcl_steps:
        Ordered list of TCL operation identifiers that should be
        executed to bring the session up to date.
    """

    full: bool
    layers: list[str] = field(default_factory=list)
    tcl_steps: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Sync policy
# ---------------------------------------------------------------------------

class SyncPolicy:
    """Determine staleness and plan refreshes for sessions.

    Parameters
    ----------
    layered_hash:
        :class:`~.hash.LayeredHash` instance for computing current
        source hashes.
    """

    def __init__(self, layered_hash: LayeredHash) -> None:
        self._hash = layered_hash

    # ------------------------------------------------------------------
    # Preflight
    # ------------------------------------------------------------------

    def preflight_check(
        self, session: Session, operation: str
    ) -> PreflightResult:
        """Check whether a session is fresh enough for the given operation.

        Parameters
        ----------
        session:
            The session to check.
        operation:
            One of ``"sim"``, ``"bitstream"``, ``"program"``,
            ``"archive"``, etc.

        Returns
        -------
        PreflightResult
        """
        # A session with no stored hashes has never been created —
        # staleness is meaningless; the project simply doesn't exist yet.
        if not session.meta.hashes:
            return PreflightResult(
                ok=False,
                reason="Session has no project; create first",
                fix="Run -create before proceeding",
                severity="error",
                stale_layers=[],
            )

        staleness = self._hash.compute_staleness(session.meta.hashes)
        stale_layers = [layer for layer, is_stale in staleness.items() if is_stale]

        if not stale_layers:
            return PreflightResult(ok=True, severity="ok", stale_layers=[])

        # RTL staleness is always a hard error — requires full rebuild.
        if staleness.get("rtl", False):
            return PreflightResult(
                ok=False,
                reason="RTL layer has changed; full rebuild required",
                fix="Run refresh (full) before proceeding",
                severity="error",
                stale_layers=stale_layers,
            )

        # Operation-specific warnings.
        if staleness.get("tb", False) and operation in ("sim",):
            return PreflightResult(
                ok=True,
                reason="TB layer has changed; incremental refresh recommended",
                fix="Run refresh (incremental, layers=['tb'])",
                severity="warning",
                stale_layers=stale_layers,
            )

        if staleness.get("coe", False) and operation in ("sim",):
            return PreflightResult(
                ok=True,
                reason="COE layer has changed; incremental refresh recommended",
                fix="Run refresh (incremental, layers=['coe'])",
                severity="warning",
                stale_layers=stale_layers,
            )

        if staleness.get("fpga", False) and operation in ("bitstream",):
            return PreflightResult(
                ok=True,
                reason="FPGA layer has changed; incremental refresh recommended",
                fix="Run refresh (incremental, layers=['fpga'])",
                severity="warning",
                stale_layers=stale_layers,
            )

        # Stale but not relevant to this operation — proceed with info.
        return PreflightResult(
            ok=True,
            reason=f"Layers {stale_layers} changed but not relevant to {operation!r}",
            severity="ok",
            stale_layers=stale_layers,
        )

    # ------------------------------------------------------------------
    # Refresh planning
    # ------------------------------------------------------------------

    def plan_refresh(
        self, staleness: dict[str, bool], task: TaskConfig
    ) -> RefreshPlan:
        """Derive a refresh plan from staleness information.

        Parameters
        ----------
        staleness:
            ``{layer: is_stale}`` mapping (from
            :meth:`~.hash.LayeredHash.compute_staleness`).
        task:
            The task configuration (used to determine which steps are
            relevant).

        Returns
        -------
        RefreshPlan
        """
        stale_layers = [layer for layer, is_stale in staleness.items() if is_stale]

        if not stale_layers:
            return RefreshPlan(full=False, layers=[], tcl_steps=[])

        # RTL stale → full rebuild.
        if staleness.get("rtl", False):
            return RefreshPlan(
                full=True,
                layers=stale_layers,
                tcl_steps=[
                    "close_project",
                    "delete_project_dir",
                    "create_project",
                    "setup_ip",
                    "add_constrs",
                    "add_tb",
                ],
            )

        # Incremental: merge steps for each stale layer.
        tcl_steps: list[str] = []
        layers_to_refresh: list[str] = []

        if staleness.get("tb", False):
            layers_to_refresh.append("tb")
            tcl_steps.extend([
                "remove_files_sim_1",
                "add_tb",
                "set_property_top",
                "update_compile_order",
                "update_coe",
            ])

        if staleness.get("coe", False):
            layers_to_refresh.append("coe")
            tcl_steps.extend([
                "set_property_coe",
                "generate_target",
            ])

        if staleness.get("fpga", False):
            layers_to_refresh.append("fpga")
            tcl_steps.extend([
                "remove_constrs",
                "add_constrs",
            ])

        return RefreshPlan(
            full=False,
            layers=layers_to_refresh,
            tcl_steps=tcl_steps,
        )
