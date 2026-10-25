"""The shared runner: every admcp tool that touches Active Directory goes through here.

It runs one fixed PowerShell script from ``scripts/``, passes the arguments as a single JSON object on stdin (agent
text never reaches a command line, ``Invoke-Expression`` or a script block), reads one JSON object back from stdout,
returns AD errors word for word, caps results at 200 rows, and records the call (calllog.py). SolutionDesign.md
section 4.2; the rules are in CLAUDE.md ("How every tool is built").
"""
import json
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

from mcp.server.mcpserver.exceptions import ToolError as _SDKToolError

from . import calllog

SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"
ROW_CAP = 200
TIMEOUT_S = 60


class ToolError(_SDKToolError):
    """A tool failed. The message is the AD or validation error, verbatim.

    It must subclass the SDK's ToolError: the SDK passes a ToolError's text to the agent ("Error executing tool <name>:
    <text>") but treats any other exception as a crash and hides its text (found on CLIENT01, 24 Oct)."""


def log_call(tool: str, args: dict, caller: str, outcome: str, error: str = "", duration_s: float = 0.0,
             rows=None, trimmed: bool = False) -> None:
    """One call-log line (CLAUDE.md rule 7). Every tool call ends here, including refused ones."""
    calllog.record({
        "ts": datetime.now(timezone.utc).isoformat(),
        "tool": tool,
        "arguments": args,
        "caller": caller,
        "outcome": outcome,
        "error": error,
        "duration_s": duration_s,
        "rows": rows,
        "trimmed": trimmed,
    })


def reject(tool: str, args: dict, caller: str, message: str) -> None:
    """Refuse a call on input shape: log it as "rejected", then raise. Refusals are red-team evidence too."""
    log_call(tool, args, caller, "rejected", message)
    raise ToolError(message)


def run_script(tool: str, args: dict, caller: str = "") -> dict:
    """Run scripts/<tool>.ps1 with ``args`` as JSON on stdin and return the JSON object it prints.

    On a non-zero exit or empty output the script's stderr (the AD error) is raised as a ToolError, unchanged. Every
    call, success or failure, writes one line to the call log in the ``finally`` block.
    """
    script = SCRIPTS / f"{tool}.ps1"
    start = time.monotonic()
    outcome, error, rows, trimmed, stdout = "ok", "", None, False, ""
    try:
        if not script.exists():
            raise ToolError(f"script not found: {script.name}")
        proc = subprocess.run(
            ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(script)],
            input=json.dumps(args, ensure_ascii=False), capture_output=True, text=True, timeout=TIMEOUT_S,
        )
        stdout = (proc.stdout or "").strip()
        if proc.returncode != 0 or not stdout:
            raise ToolError((proc.stderr or stdout or f"the script exited with code {proc.returncode}").strip())
        result = json.loads(stdout)
        if isinstance(result, dict) and isinstance(result.get("rows"), list):
            if len(result["rows"]) > ROW_CAP:
                result["rows"] = result["rows"][:ROW_CAP]
                result["trimmed"] = True
            rows = len(result["rows"])
            trimmed = bool(result.get("trimmed"))
        return result
    except ToolError as exc:
        outcome, error = "error", str(exc)
        raise
    except json.JSONDecodeError:
        outcome, error = "error", f"the script did not return JSON: {stdout[:500]}"
        raise ToolError(error)
    except subprocess.TimeoutExpired:
        outcome, error = "error", f"the script timed out after {TIMEOUT_S}s"
        raise ToolError(error)
    finally:
        log_call(tool, args, caller, outcome, error, round(time.monotonic() - start, 3), rows, trimmed)
