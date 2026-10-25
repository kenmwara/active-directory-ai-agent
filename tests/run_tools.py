"""Call every admcp tool over stdio, the way Claude Code does, and print each result (trimmed).

Run ON CLIENT01 as KENLAB\\ai-operator (the agent's identity), from C:\\ADAgent:
    .venv\\Scripts\\python tests\\run_tools.py <a group in OU=Groups>
Each tool gets a happy-path call and a call that must be refused (input validation) or come back with AD's own error.
"""
import asyncio
import json
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path(__file__).resolve().parent.parent


def calls(group: str) -> list:
    return [
        ("happy", "ad_whoami", {}),
        ("happy", "ad_search_users", {"locked_only": True}),
        ("happy (trim)", "ad_search_users", {}),
        ("refused", "ad_search_users", {"name": "x' -or Name -like '*"}),
        ("refused", "ad_search_users", {"department": "Sales"}),
        ("happy", "ad_get_group_members", {"group": group}),
        ("AD error", "ad_get_group_members", {"group": "no-such-group-zz"}),
        ("privileged read", "ad_get_group_members", {"group": "Domain Admins"}),
        ("happy", "admcp_my_tool_calls", {"limit": 10}),
    ]


async def main(group: str) -> None:
    params = StdioServerParameters(command=sys.executable, args=["-m", "admcp.server"], cwd=str(ROOT))
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            for label, name, args in calls(group):
                res = await session.call_tool(name, args)
                text = " ".join(getattr(c, "text", "") for c in res.content)
                print(f"--- {label}: {name} {json.dumps(args)} isError={getattr(res, 'isError', None)}")
                print(text[:1200])


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else "AI-Operators"))
