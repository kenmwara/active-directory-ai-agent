"""Runnable check: start admcp over stdio, list its tools, compare with the expected set; and start it with forged
USERNAME/USERDOMAIN values to prove the call log's caller comes from the Windows token, not the environment.

Usage (repo root): python tests/check_server.py
"""
import asyncio
import getpass
import json
import sys
import tempfile
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path(__file__).resolve().parent.parent
EXPECTED: set[str] = {
    "ad_whoami", "admcp_my_tool_calls", "ad_search_users", "ad_get_group_members",       # Phase 3, read-only
    "ad_unlock_account", "ad_add_group_member", "ad_disable_account",                   # Phase 5, change + destructive
}


async def tool_names() -> set[str]:
    params = StdioServerParameters(command=sys.executable, args=["-m", "admcp.server"], cwd=str(ROOT))
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            return {t.name for t in (await session.list_tools()).tools}


async def logged_caller_with_forged_env(calllog: Path) -> str:
    env = {"USERNAME": "forged-user", "USERDOMAIN": "FORGED", "ADMCP_CALLLOG": str(calllog)}
    params = StdioServerParameters(command=sys.executable, args=["-m", "admcp.server"], cwd=str(ROOT), env=env)
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            await session.call_tool("ad_search_users", {"department": "Sales"})   # refused by shape: no AD needed
            res = await session.call_tool("admcp_my_tool_calls", {"limit": 5})
            return json.loads(res.content[0].text)["rows"][-1]["caller"]


if __name__ == "__main__":
    names = asyncio.run(tool_names())
    assert names == EXPECTED, f"tools {sorted(names)} != expected {sorted(EXPECTED)}"
    print(f"ok: admcp started over stdio, {len(names)} tools")
    with tempfile.TemporaryDirectory() as d:
        caller = asyncio.run(logged_caller_with_forged_env(Path(d) / "calls.jsonl"))
    assert "forged" not in caller.lower() and caller.lower().endswith("\\" + getpass.getuser().lower()), caller
    print(f"ok: caller {caller!r} comes from the Windows token, forged USERNAME/USERDOMAIN ignored")
