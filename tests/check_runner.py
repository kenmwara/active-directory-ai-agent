"""Runnable check for the shared runner, no domain needed: the 200-row cap, AD errors passed through word for word,
and one call-log line per call (including refused ones). Uses stub scripts in a temp dir, so it runs on the host.

Usage (repo root, Windows): python tests/check_runner.py
"""
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
tmp = Path(tempfile.mkdtemp())
os.environ["ADMCP_CALLLOG"] = str(tmp / "calls.jsonl")

from admcp import calllog, runner  # noqa: E402  (after ADMCP_CALLLOG is set)

runner.SCRIPTS = tmp
(tmp / "rows.ps1").write_text(
    "$n = ([Console]::In.ReadToEnd() | ConvertFrom-Json).n\n"
    "@{ count = $n; rows = @(1..$n) } | ConvertTo-Json -Compress\n", encoding="utf-8")
(tmp / "deny.ps1").write_text('[Console]::Error.WriteLine("Access is denied"); exit 1\n', encoding="utf-8")

big = runner.run_script("rows", {"n": 250}, "t")
assert len(big["rows"]) == 200 and big["trimmed"] is True and big["count"] == 250, big
small = runner.run_script("rows", {"n": 3}, "t")
assert small["rows"] == [1, 2, 3] and "trimmed" not in small, small
try:
    runner.run_script("deny", {}, "t")
    raise SystemExit("FAIL: a denied script must raise")
except runner.ToolError as exc:
    assert str(exc) == "Access is denied", repr(str(exc))
try:
    runner.reject("ad_search_users", {"name": "x';y"}, "t", "name has characters that are not allowed")
    raise SystemExit("FAIL: reject must raise")
except runner.ToolError:
    pass

# the SDK only shows a ToolError's text to the agent; any other exception reaches it as a bare "Error executing tool"
from mcp.server.mcpserver.exceptions import ToolError as SDKToolError  # noqa: E402
assert issubclass(runner.ToolError, SDKToolError), "runner.ToolError must subclass the SDK's ToolError"

log = calllog.read_recent(10)
assert [e["outcome"] for e in log] == ["ok", "ok", "error", "rejected"], log
assert log[0]["rows"] == 200 and log[0]["trimmed"] is True, log[0]
assert log[2]["error"] == "Access is denied" and log[3]["arguments"] == {"name": "x';y"}, log[2:]
print("ok: runner caps at 200, passes AD errors verbatim, logs all 4 calls (incl. the refused one)")
