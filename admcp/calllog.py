"""The admcp call log: one JSON line per tool call, plus a best-effort Application event-log entry.

Every admcp tool call is recorded here by runner.py (SolutionDesign.md section 4.2, point 8): timestamp, tool,
arguments, caller, outcome, error text, duration, rows, trimmed. The log is the agent's own history; the
``admcp_my_tool_calls`` tool reads it back. DC01's Security log is the ground truth (D13), because this file is
writable by the same identity the agent runs as.
"""
import json
import os
import subprocess
from pathlib import Path


def log_path() -> Path:
    """Where the call log lives. ADMCP_CALLLOG overrides; otherwise a per-user file so a read-only repo dir is fine."""
    override = os.environ.get("ADMCP_CALLLOG")
    if override:
        return Path(override)
    base = os.environ.get("LOCALAPPDATA") or os.environ.get("TEMP") or str(Path.home())
    return Path(base) / "admcp" / "calls.jsonl"


def record(entry: dict) -> None:
    """Append one JSON line to the call log, then try the Application event log. Never raises: a logging failure
    must not break a tool call (and must not hide the tool's own error)."""
    line = json.dumps(entry, ensure_ascii=False)
    path = log_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except OSError:
        pass
    # Application event log, source "admcp" (registered by lab/setup-lab.ps1). The message is passed through an
    # environment variable, never the command line, so nothing in the log entry can be read as a PowerShell command.
    try:
        env = dict(os.environ)
        env["ADMCP_EVT"] = line[:30000]
        subprocess.run(
            ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
             "Write-EventLog -LogName Application -Source admcp -EventId 7000 -EntryType Information -Message $env:ADMCP_EVT"],
            capture_output=True, timeout=10, env=env,
        )
    except Exception:
        pass


def read_recent(limit: int = 50) -> list:
    """The last ``limit`` call-log entries, oldest first. Bad lines are skipped, not raised."""
    path = log_path()
    if not path.exists():
        return []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return []
    out = []
    for ln in lines[-limit:]:
        try:
            out.append(json.loads(ln))
        except ValueError:
            pass
    return out
