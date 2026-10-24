"""Runnable check: start admcp over stdio, list its tools, compare with the expected set.

Usage (repo root): python tests/check_server.py
"""
import asyncio
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path(__file__).resolve().parent.parent
EXPECTED: set[str] = {"ad_whoami", "admcp_my_tool_calls", "ad_search_users", "ad_get_group_members"}


async def tool_names() -> set[str]:
    params = StdioServerParameters(command=sys.executable, args=["-m", "admcp.server"], cwd=str(ROOT))
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            return {t.name for t in (await session.list_tools()).tools}


if __name__ == "__main__":
    names = asyncio.run(tool_names())
    assert names == EXPECTED, f"tools {sorted(names)} != expected {sorted(EXPECTED)}"
    print(f"ok: admcp started over stdio, {len(names)} tools")
