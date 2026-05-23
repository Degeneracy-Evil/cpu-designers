#!/usr/bin/env python3
"""Vivado Orchestrator TUI — terminal UI for human-friendly Vivado interaction.

Uses the `textual` framework to provide:
  - Session list panel with status/staleness indicators
  - Task selector dropdown (from tasks.yaml)
  - Command input with basic TCL completion
  - Vivado output viewer (scrollable, real-time)
  - Action buttons for common operations

Usage:
    python tools/vivado_tui.py
"""
from __future__ import annotations

import sys
import time
from pathlib import Path
from typing import TYPE_CHECKING

# ---------------------------------------------------------------------------
# textual availability check
# ---------------------------------------------------------------------------
try:
    from textual import work
    from textual.app import App, ComposeResult
    from textual.binding import Binding
    from textual.containers import Container, Horizontal, Vertical
    from textual.events import Key
    from textual.reactive import reactive
    from textual.widgets import (
        Button,
        Footer,
        Header,
        Input,
        Label,
        RichLog,
        Select,
        Static,
    )
except ImportError:
    print(
        "ERROR: The 'textual' framework is not installed.\n"
        "       Install it with:  pip install textual\n"
        "       Then re-run this script.",
        file=sys.stderr,
    )
    sys.exit(1)

# ---------------------------------------------------------------------------
# vivado_core import — graceful degradation
# ---------------------------------------------------------------------------
try:
    from tools.vivado_core import (
        LayeredHash,
        Operations,
        SessionManager,
        SyncPolicy,
        TaskRegistry,
        VivadoCoreError,
    )
    from tools.vivado_core.config import GlobalConfig, load_config
    from tools.vivado_core.session import ExecuteResult, Session, SessionMeta
    from tools.vivado_core.sync import PreflightResult

    _HAS_CORE = True
except ImportError:
    _HAS_CORE = False

    class VivadoCoreError(Exception):  # type: ignore[no-redef]
        """Placeholder when vivado_core is not available."""

    class GlobalConfig:  # type: ignore[no-redef]
        def __init__(self, *a, **kw): pass

    class SessionManager:  # type: ignore[no-redef]
        def __init__(self, *a, **kw): pass

    class TaskRegistry:  # type: ignore[no-redef]
        def __init__(self, *a, **kw): pass

    class LayeredHash:  # type: ignore[no-redef]
        def __init__(self, *a, **kw): pass

    class SyncPolicy:  # type: ignore[no-redef]
        def __init__(self, *a, **kw): pass

    class Operations:  # type: ignore[no-redef]
        def __init__(self, *a, **kw): pass

    class Session:  # type: ignore[no-redef]
        def __init__(self, *a, **kw): pass

    class SessionMeta:  # type: ignore[no-redef]
        def __init__(self, *a, **kw): pass

    class PreflightResult:  # type: ignore[no-redef]
        def __init__(self, *a, **kw): pass

    class ExecuteResult:  # type: ignore[no-redef]
        def __init__(self, *a, **kw): pass

    def load_config(*a, **kw):  # type: ignore[no-redef]
        return GlobalConfig()


# ---------------------------------------------------------------------------
# Static TCL command list for tab-completion
# ---------------------------------------------------------------------------
COMMON_TCL_COMMANDS: list[str] = sorted([
    # Vivado project commands
    "create_project",
    "open_project",
    "close_project",
    "current_project",
    # File management
    "add_files",
    "remove_files",
    "import_files",
    "update_compile_order",
    "set_property",
    "get_property",
    # Simulation
    "launch_simulation",
    "close_sim",
    "current_sim",
    "restart_sim",
    "run_sim",
    # Synthesis / implementation
    "launch_runs",
    "wait_on_run",
    "reset_run",
    # Hardware
    "open_hw",
    "connect_hw_server",
    "open_hw_target",
    "program_hw_devices",
    # Utility
    "puts",
    "source",
    "quit",
    # Custom orchestration
    "source _create.tcl",
    "source _sim.tcl",
    "source _bitstream.tcl",
])


# ---------------------------------------------------------------------------
# Project root resolution
# ---------------------------------------------------------------------------
def _project_root() -> Path:
    """Resolve the project root (repo checkout directory)."""
    return Path(__file__).resolve().parent.parent


# ---------------------------------------------------------------------------
# SessionPanel — lists sessions with status/staleness
# ---------------------------------------------------------------------------
class SessionPanel(Vertical):
    """Left panel showing all sessions with status indicators."""

    DEFAULT_CSS = """
    SessionPanel {
        width: 36;
        min-width: 28;
        border: solid green;
        padding: 0 1;
    }
    SessionPanel > .session-title {
        text-style: bold;
        color: $text-primary;
        padding: 0 0 1 0;
    }
    SessionPanel > .session-entry {
        padding: 0 1;
    }
    SessionPanel > .session-entry:selected {
        background: $surface-2;
        text-style: bold;
    }
    SessionPanel > .session-entry:hover {
        background: $surface-1;
    }
    .status-idle { color: $success; }
    .status-busy { color: $warning; }
    .status-error { color: $error; }
    .stale-layer { color: $warning; text-style: italic; }
    """

    selected_session: reactive[str | None] = reactive(None)

    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self._session_data: list[dict] = []

    def compose(self) -> ComposeResult:
        yield Label("Sessions", classes="session-title")

    def update_sessions(self, sessions: list, stale_map: dict[str, list[str]] | None = None) -> None:
        """Refresh the session list display.

        Parameters
        ----------
        sessions:
            List of Session objects from SessionManager.list_sessions().
        stale_map:
            Optional mapping of session_name → list of stale layer names.
        """
        if stale_map is None:
            stale_map = {}

        # Remove old entries (keep the title label)
        for child in list(self.children)[1:]:
            child.remove()

        self._session_data = []
        for sess in sessions:
            name = sess.name if hasattr(sess, "name") else str(sess)
            meta = sess.meta if hasattr(sess, "meta") else None
            task = meta.task if meta else "?"
            status = meta.status if meta else "idle"
            pid = meta.vivado_pid if meta else None
            stale_layers = stale_map.get(name, [])

            # Build display line
            indicator = {"idle": "●", "busy": "◆", "error": "✖"}.get(status, "○")
            line = f" {indicator} {name:<16} {status:<6}"
            if pid:
                line += f" PID:{pid}"
            if stale_layers:
                line += f"  stale: {','.join(stale_layers)}"

            entry = Static(line, classes="session-entry")
            # Apply status class for coloring
            status_class = f"status-{status}"
            entry.add_class(status_class)
            if stale_layers:
                entry.add_class("stale-layer")

            # Store data for click handling
            self._session_data.append({"name": name, "status": status, "stale": stale_layers})

            # Click handler via lambda capturing name
            entry.on_click = lambda event, n=name: self._on_entry_click(n)  # type: ignore[assignment]
            self.mount(entry)

    def _on_entry_click(self, name: str) -> None:
        """Handle click on a session entry."""
        self.selected_session = name
        # Highlight selected
        for child in list(self.children)[1:]:
            child.remove_class("selected")
        for i, child in enumerate(list(self.children)[1:]):
            if i < len(self._session_data) and self._session_data[i]["name"] == name:
                child.add_class("selected")


# ---------------------------------------------------------------------------
# TaskSelector — dropdown for task selection
# ---------------------------------------------------------------------------
class TaskSelector(Vertical):
    """Task selection dropdown populated from TaskRegistry."""

    DEFAULT_CSS = """
    TaskSelector {
        padding: 0 1;
        height: auto;
    }
    TaskSelector > Label {
        text-style: bold;
        margin: 0 0 1 0;
    }
    TaskSelector > Select {
        width: 100%;
    }
    """

    selected_task: reactive[str | None] = reactive(None)

    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)

    def compose(self) -> ComposeResult:
        yield Label("Task")
        yield Select(
            options=[("(no tasks loaded)", None)],
            value=None,
            id="task-select",
        )

    def update_tasks(self, task_names: list[str]) -> None:
        """Populate the dropdown with task names."""
        select = self.query_one("#task-select", Select)
        options = [(name, name) for name in task_names]
        if not options:
            options = [("(no tasks loaded)", None)]
        select.set_options(options)
        if task_names:
            select.value = task_names[0]
            self.selected_task = task_names[0]

    def on_select_changed(self, event: Select.Changed) -> None:
        """React to task selection change."""
        if event.select.id == "task-select":
            self.selected_task = event.value


# ---------------------------------------------------------------------------
# ControlPanel — action buttons
# ---------------------------------------------------------------------------
class ControlPanel(Vertical):
    """Right panel with action buttons for common operations."""

    DEFAULT_CSS = """
    ControlPanel {
        width: 1fr;
        border: solid blue;
        padding: 0 1;
    }
    ControlPanel > .ctrl-title {
        text-style: bold;
        color: $text-primary;
        padding: 0 0 1 0;
    }
    ControlPanel > .ctrl-session-label {
        padding: 0 0 1 0;
        color: $text-secondary;
    }
    ControlPanel > Horizontal {
        height: auto;
        margin: 0 0 1 0;
    }
    ControlPanel > Horizontal > Button {
        margin: 0 1 0 0;
        min-width: 12;
    }
    .btn-create { background: $success; }
    .btn-sim { background: $primary; }
    .btn-refresh { background: $accent; }
    .btn-bitstream { background: $warning; }
    .btn-program { background: $error; }
    .btn-archive { background: $surface-2; }
    """

    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)

    def compose(self) -> ComposeResult:
        yield Label("Control", classes="ctrl-title")
        yield Label("Session: (none)", id="ctrl-session-name", classes="ctrl-session-label")
        with Horizontal():
            yield Button("Create", id="btn-create", classes="btn-create")
            yield Button("Sim", id="btn-sim", classes="btn-sim")
            yield Button("Refresh", id="btn-refresh", classes="btn-refresh")
        with Horizontal():
            yield Button("Bitstream", id="btn-bitstream", classes="btn-bitstream")
            yield Button("Program", id="btn-program", classes="btn-program")
            yield Button("Archive", id="btn-archive", classes="btn-archive")

    def set_session_name(self, name: str | None) -> None:
        """Update the session name label."""
        label = self.query_one("#ctrl-session-name", Label)
        label.update(f"Session: {name or '(none)'}")

    def set_buttons_enabled(self, enabled: bool) -> None:
        """Enable or disable all action buttons."""
        for btn_id in ("btn-create", "btn-sim", "btn-refresh",
                       "btn-bitstream", "btn-program", "btn-archive"):
            try:
                btn = self.query_one(f"#{btn_id}", Button)
                btn.disabled = not enabled
            except Exception:
                pass


# ---------------------------------------------------------------------------
# CommandInput — TCL command entry with basic completion
# ---------------------------------------------------------------------------
class CommandInput(Vertical):
    """Command input field for raw TCL commands."""

    DEFAULT_CSS = """
    CommandInput {
        height: 3;
        border: solid yellow;
        padding: 0 1;
    }
    CommandInput > Input {
        width: 100%;
    }
    """

    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self._completion_index: int = 0
        self._completion_matches: list[str] = []

    def compose(self) -> ComposeResult:
        yield Input(placeholder="> Enter TCL command (Tab to complete)...", id="tcl-input")

    def on_key(self, event: Key) -> None:
        """Handle Tab key for completion."""
        if event.key == "tab":
            event.prevent_default()
            self._do_completion()

    def _do_completion(self) -> None:
        """Perform basic tab-completion against COMMON_TCL_COMMANDS."""
        try:
            inp = self.query_one("#tcl-input", Input)
        except Exception:
            return
        current = inp.value or ""
        if not current:
            return

        # Find matching commands
        matches = [cmd for cmd in COMMON_TCL_COMMANDS if cmd.startswith(current)]
        if not matches:
            return

        # Cycle through matches
        if current != self._completion_matches[self._completion_index - 1] if self._completion_matches else True:
            self._completion_matches = matches
            self._completion_index = 0

        self._completion_index = (self._completion_index + 1) % len(self._completion_matches)
        inp.value = self._completion_matches[self._completion_index]
        # Move cursor to end
        inp.cursor_position = len(inp.value)


# ---------------------------------------------------------------------------
# OutputViewer — scrollable Vivado output
# ---------------------------------------------------------------------------
class OutputViewer(Vertical):
    """Scrollable output viewer for Vivado output."""

    DEFAULT_CSS = """
    OutputViewer {
        height: 1fr;
        border: solid white;
        padding: 0 1;
    }
    OutputViewer > .output-title-bar {
        height: 1;
        dock: top;
    }
    OutputViewer > .output-title-bar > Label {
        text-style: bold;
    }
    OutputViewer > .output-title-bar > Button {
        dock: right;
        min-width: 8;
    }
    OutputViewer > RichLog {
        height: 1fr;
        scrollbar-size: 1 1;
    }
    """

    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)

    def compose(self) -> ComposeResult:
        with Horizontal(classes="output-title-bar"):
            yield Label("Output")
            yield Button("Clear", id="btn-clear-output", variant="default")
        yield RichLog(id="vivado-output", highlight=True, markup=True)

    def write(self, text: str) -> None:
        """Append text to the output viewer."""
        try:
            log = self.query_one("#vivado-output", RichLog)
            log.write(text)
        except Exception:
            pass

    def write_error(self, text: str) -> None:
        """Append error text (styled red) to the output viewer."""
        try:
            log = self.query_one("#vivado-output", RichLog)
            log.write(f"[bold red]{text}[/bold red]")
        except Exception:
            pass

    def write_warning(self, text: str) -> None:
        """Append warning text (styled yellow) to the output viewer."""
        try:
            log = self.query_one("#vivado-output", RichLog)
            log.write(f"[bold yellow]{text}[/bold yellow]")
        except Exception:
            pass

    def clear_output(self) -> None:
        """Clear the output viewer."""
        try:
            log = self.query_one("#vivado-output", RichLog)
            log.clear()
        except Exception:
            pass

    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle Clear button."""
        if event.button.id == "btn-clear-output":
            self.clear_output()


# ---------------------------------------------------------------------------
# Main TUI Application
# ---------------------------------------------------------------------------
class VivadoTUI(App):
    """Vivado Orchestrator TUI — terminal interface for Vivado workflows."""

    CSS = """
    Screen {
        layout: vertical;
    }

    #main-area {
        layout: horizontal;
        height: 14;
    }

    #sessions-panel {
        width: 36;
        border: solid green;
    }

    #right-area {
        layout: vertical;
        width: 1fr;
    }

    #control-panel {
        width: 1fr;
        border: solid blue;
    }

    #command-area {
        height: 3;
        border: solid yellow;
    }

    #output-area {
        height: 1fr;
        border: solid white;
    }
    """

    TITLE = "Vivado Orchestrator"
    SUB_TITLE = "Session-based Vivado workflow management"

    BINDINGS = [
        Binding("ctrl+q", "quit", "Quit", show=True),
        Binding("ctrl+r", "refresh_sessions", "Refresh", show=True),
        Binding("ctrl+l", "clear_output", "Clear Output", show=True),
    ]

    # Reactive state
    current_session_name: reactive[str | None] = reactive(None)
    current_task_name: reactive[str | None] = reactive(None)

    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self._project_root = _project_root()
        self._session_mgr: SessionManager | None = None
        self._task_registry: TaskRegistry | None = None
        self._layered_hash: LayeredHash | None = None
        self._sync: SyncPolicy | None = None
        self._ops: Operations | None = None
        self._config: GlobalConfig | None = None
        self._current_session: Session | None = None
        self._stale_map: dict[str, list[str]] = {}

    def compose(self) -> ComposeResult:
        """Build the application layout."""
        yield Header()
        with Horizontal(id="main-area"):
            yield SessionPanel(id="sessions-panel")
            with Vertical(id="right-area"):
                yield TaskSelector(id="task-selector")
                yield ControlPanel(id="control-panel")
        yield CommandInput(id="command-area")
        yield OutputViewer(id="output-area")
        yield Footer()

    def on_mount(self) -> None:
        """Initialize core components and start auto-refresh."""
        self._init_core()
        # Auto-refresh sessions every 5 seconds
        self.set_interval(5, self._refresh_sessions, name="session-refresh")

    def _init_core(self) -> None:
        """Initialize vivado_core components (lazy, non-blocking)."""
        if not _HAS_CORE:
            self._output_write("WARNING: vivado_core not available — operations disabled")
            return

        try:
            config_path = self._project_root / "vivado_config.yaml"
            tasks_path = self._project_root / "tasks.yaml"

            self._config = load_config(config_path, self._project_root)
            self._task_registry = TaskRegistry(tasks_path)
            self._task_registry.load()
            self._session_mgr = SessionManager(self._project_root, self._config)
            self._layered_hash = LayeredHash(self._project_root)
            self._sync = SyncPolicy(self._layered_hash)
            self._ops = Operations(
                self._session_mgr, self._task_registry,
                self._sync, self._layered_hash,
            )

            # Populate task selector
            task_names = self._task_registry.list_names()
            task_sel = self.query_one("#task-selector", TaskSelector)
            task_sel.update_tasks(task_names)

            # Initial session refresh
            self._refresh_sessions()

            self._output_write("Core initialized. Tasks: " + ", ".join(task_names))

        except VivadoCoreError as e:
            self._output_write_error(f"Core init error: {e}")
        except Exception as e:
            self._output_write_error(f"Unexpected init error: {e}")

    # ------------------------------------------------------------------
    # Session management
    # ------------------------------------------------------------------

    def _refresh_sessions(self) -> None:
        """Refresh the session list panel (called by interval and manually)."""
        if not self._session_mgr:
            return
        try:
            sessions = self._session_mgr.list_sessions()
            # Compute staleness for each session
            stale_map: dict[str, list[str]] = {}
            if self._layered_hash:
                for sess in sessions:
                    if hasattr(sess, "meta") and sess.meta.hashes:
                        staleness = self._layered_hash.compute_staleness(sess.meta.hashes)
                        stale_layers = [k for k, v in staleness.items() if v]
                        if stale_layers:
                            stale_map[sess.name] = stale_layers
            self._stale_map = stale_map

            panel = self.query_one("#sessions-panel", SessionPanel)
            panel.update_sessions(sessions, stale_map)

        except VivadoCoreError as e:
            self._output_write_error(f"Session refresh error: {e}")
        except Exception as e:
            # Silently ignore errors during auto-refresh to avoid spamming
            pass

    def _get_or_create_session(self, task_name: str, session_name: str | None = None) -> Session | None:
        """Get or create a session for the given task."""
        if not self._session_mgr:
            self._output_write_error("Session manager not initialized")
            return None
        try:
            name = session_name or task_name
            session = self._session_mgr.get_or_create(task_name, name, self._task_registry)
            self._current_session = session
            self.current_session_name = session.name
            ctrl = self.query_one("#control-panel", ControlPanel)
            ctrl.set_session_name(session.name)
            ctrl.set_buttons_enabled(True)
            return session
        except VivadoCoreError as e:
            self._output_write_error(f"Session error: {e}")
            return None

    def _resolve_session(self) -> Session | None:
        """Resolve the current session (from selection or create new)."""
        if self._current_session:
            return self._current_session

        task_name = self.current_task_name
        if not task_name:
            self._output_write_error("No task selected — select a task first")
            return None

        return self._get_or_create_session(task_name)

    # ------------------------------------------------------------------
    # Preflight checks
    # ------------------------------------------------------------------

    def _check_staleness(self, session: Session, operation: str) -> PreflightResult | None:
        """Run preflight check and display warnings.

        Returns None if the check cannot be performed.
        """
        if not self._sync:
            return None
        try:
            result = self._sync.preflight_check(session, operation)
            if result.stale_layers:
                self._output_write_warning(
                    f"Staleness detected for {operation}: "
                    f"layers {result.stale_layers} — {result.reason}"
                )
                if result.severity == "error":
                    self._output_write_error(
                        f"Preflight FAILED: {result.reason}. {result.fix}"
                    )
            return result
        except VivadoCoreError as e:
            self._output_write_error(f"Preflight error: {e}")
            return None

    # ------------------------------------------------------------------
    # Operation workers
    # ------------------------------------------------------------------

    @work(exclusive=True)
    async def _do_create(self) -> None:
        """Worker: create project in session."""
        session = self._resolve_session()
        if not session or not self._ops or not self._task_registry:
            return
        task_name = self.current_task_name or session.meta.task
        try:
            task = self._task_registry.get(task_name)
        except VivadoCoreError as e:
            self._output_write_error(f"Task error: {e}")
            return

        self._output_write(f"========== Create: {session.name} (task: {task_name}) ==========")
        t0 = time.monotonic()
        try:
            result = self._ops.create(session, task)
            self._output_write(result.output)
            if not result.success:
                self._output_write_error(f"Create failed (duration: {result.duration:.1f}s)")
            else:
                self._output_write(f"Create succeeded ({result.duration:.1f}s)")
        except VivadoCoreError as e:
            self._output_write_error(f"Create error: {e}")
        duration = time.monotonic() - t0
        self._refresh_sessions()

    @work(exclusive=True)
    async def _do_sim(self) -> None:
        """Worker: run simulation."""
        session = self._resolve_session()
        if not session or not self._ops or not self._task_registry:
            return
        task_name = self.current_task_name or session.meta.task
        try:
            task = self._task_registry.get(task_name)
        except VivadoCoreError as e:
            self._output_write_error(f"Task error: {e}")
            return

        # Preflight
        preflight = self._check_staleness(session, "sim")
        if preflight and not preflight.ok:
            return

        self._output_write(f"========== Sim: {session.name} (task: {task_name}) ==========")
        t0 = time.monotonic()
        try:
            result = self._ops.sim(session, task)
            self._output_write(result.output)
            if not result.success:
                self._output_write_error(f"Sim failed (duration: {result.duration:.1f}s)")
            else:
                self._output_write(f"Sim succeeded ({result.duration:.1f}s)")
        except VivadoCoreError as e:
            self._output_write_error(f"Sim error: {e}")
        self._refresh_sessions()

    @work(exclusive=True)
    async def _do_refresh(self) -> None:
        """Worker: refresh session (sync source changes)."""
        session = self._resolve_session()
        if not session or not self._ops:
            return

        self._output_write(f"========== Refresh: {session.name} ==========")
        t0 = time.monotonic()
        try:
            result = self._ops.refresh(session)
            self._output_write(result.output)
            if not result.success:
                self._output_write_error(f"Refresh failed (duration: {result.duration:.1f}s)")
            else:
                self._output_write(f"Refresh succeeded ({result.duration:.1f}s)")
        except VivadoCoreError as e:
            self._output_write_error(f"Refresh error: {e}")
        self._refresh_sessions()

    @work(exclusive=True)
    async def _do_bitstream(self) -> None:
        """Worker: generate bitstream."""
        session = self._resolve_session()
        if not session or not self._ops:
            return

        # Preflight
        preflight = self._check_staleness(session, "bitstream")
        if preflight and not preflight.ok:
            return

        self._output_write(f"========== Bitstream: {session.name} ==========")
        t0 = time.monotonic()
        try:
            result = self._ops.bitstream(session)
            self._output_write(result.output)
            if not result.success:
                self._output_write_error(f"Bitstream failed (duration: {result.duration:.1f}s)")
            else:
                self._output_write(f"Bitstream succeeded ({result.duration:.1f}s)")
        except VivadoCoreError as e:
            self._output_write_error(f"Bitstream error: {e}")
        self._refresh_sessions()

    @work(exclusive=True)
    async def _do_program(self) -> None:
        """Worker: program FPGA."""
        session = self._resolve_session()
        if not session or not self._ops:
            return

        self._output_write(f"========== Program: {session.name} ==========")
        t0 = time.monotonic()
        try:
            result = self._ops.program(session)
            self._output_write(result.output)
            if not result.success:
                self._output_write_error(f"Program failed (duration: {result.duration:.1f}s)")
            else:
                self._output_write(f"Program succeeded ({result.duration:.1f}s)")
        except VivadoCoreError as e:
            self._output_write_error(f"Program error: {e}")
        self._refresh_sessions()

    @work(exclusive=True)
    async def _do_archive(self) -> None:
        """Worker: export project archive."""
        session = self._resolve_session()
        if not session or not self._ops:
            return

        self._output_write(f"========== Archive: {session.name} ==========")
        t0 = time.monotonic()
        try:
            result = self._ops.archive(session)
            self._output_write(result.output)
            if not result.success:
                self._output_write_error(f"Archive failed (duration: {result.duration:.1f}s)")
            else:
                self._output_write(f"Archive succeeded ({result.duration:.1f}s)")
        except VivadoCoreError as e:
            self._output_write_error(f"Archive error: {e}")
        self._refresh_sessions()

    @work(exclusive=True)
    async def _do_execute_tcl(self, cmd: str) -> None:
        """Worker: execute a raw TCL command in the current session."""
        session = self._current_session
        if not session:
            self._output_write_error("No active session — select or create one first")
            return

        self._output_write(f"> {cmd}")
        try:
            if not session.is_alive():
                session.start_vivado()
            result = session.execute(cmd, timeout=120.0)
            self._output_write(result.output)
            if not result.success:
                self._output_write_error(f"Command failed ({result.duration:.1f}s)")
        except VivadoCoreError as e:
            self._output_write_error(f"Execute error: {e}")
        self._refresh_sessions()

    # ------------------------------------------------------------------
    # Output helpers (thread-safe via call_from_thread)
    # ------------------------------------------------------------------

    def _output_write(self, text: str) -> None:
        """Write to output viewer (main-thread safe)."""
        try:
            viewer = self.query_one("#output-area", OutputViewer)
            viewer.write(text)
        except Exception:
            pass

    def _output_write_error(self, text: str) -> None:
        """Write error to output viewer (main-thread safe)."""
        try:
            viewer = self.query_one("#output-area", OutputViewer)
            viewer.write_error(text)
        except Exception:
            pass

    def _output_write_warning(self, text: str) -> None:
        """Write warning to output viewer (main-thread safe)."""
        try:
            viewer = self.query_one("#output-area", OutputViewer)
            viewer.write_warning(text)
        except Exception:
            pass

    # ------------------------------------------------------------------
    # Event handlers
    # ------------------------------------------------------------------

    def on_session_panel_selected_session_changed(self, event: SessionPanel.SelectedSessionChanged) -> None:
        """React to session selection in the panel."""
        name = event.value
        self.current_session_name = name
        ctrl = self.query_one("#control-panel", ControlPanel)
        ctrl.set_session_name(name)
        ctrl.set_buttons_enabled(name is not None)

        # Load the actual session object
        if name and self._session_mgr:
            try:
                self._current_session = self._session_mgr.get_session(name)
            except VivadoCoreError:
                self._current_session = None
        else:
            self._current_session = None

    def on_task_selector_selected_task_changed(self, event: TaskSelector.SelectedTaskChanged) -> None:
        """React to task selection change."""
        self.current_task_name = event.value
        # Update default session name in control panel
        if event.value:
            ctrl = self.query_one("#control-panel", ControlPanel)
            if not self.current_session_name:
                ctrl.set_session_name(event.value)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle action button presses."""
        btn_id = event.button.id
        if btn_id == "btn-create":
            self._do_create()
        elif btn_id == "btn-sim":
            self._do_sim()
        elif btn_id == "btn-refresh":
            self._do_refresh()
        elif btn_id == "btn-bitstream":
            self._do_bitstream()
        elif btn_id == "btn-program":
            self._do_program()
        elif btn_id == "btn-archive":
            self._do_archive()

    def on_input_submitted(self, event: Input.Submitted) -> None:
        """Handle command input submission (Enter key)."""
        if event.input.id == "tcl-input":
            cmd = event.value.strip()
            if not cmd:
                return
            self._do_execute_tcl(cmd)
            event.input.value = ""

    # ------------------------------------------------------------------
    # Actions (key bindings)
    # ------------------------------------------------------------------

    def action_refresh_sessions(self) -> None:
        """Manual session refresh (Ctrl+R)."""
        self._refresh_sessions()
        self._output_write("Sessions refreshed.")

    def action_clear_output(self) -> None:
        """Clear output viewer (Ctrl+L)."""
        try:
            viewer = self.query_one("#output-area", OutputViewer)
            viewer.clear_output()
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    app = VivadoTUI()
    app.run()
