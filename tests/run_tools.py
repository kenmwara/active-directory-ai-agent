r"""Call every admcp tool over stdio, the way Claude Code does, and print each result (trimmed).

Run ON CLIENT01 as KENLAB\ai-operator (the agent's identity), from C:\ADAgent:
    .venv\Scripts\python tests\run_tools.py C:\Users\Public\Documents\admcp\targets.json
Each tool gets a happy-path call and a call that must be refused (input validation) or come back with AD's own error.
The change tools work on the lab's own test objects (lab-inside in _USERS, lab-outside in _LABTEST); the laptop's
Evidence step re-enables lab-inside and removes it from the group afterwards.
"""
import asyncio
import json
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path(__file__).resolve().parent.parent


def calls(t: dict) -> list:
    return [
        ("happy", "ad_whoami", {}),
        ("happy", "ad_search_users", {"locked_only": True}),
        ("happy (trim)", "ad_search_users", {}),
        ("refused", "ad_search_users", {"name": "x' -or Name -like '*"}),
        ("refused", "ad_search_users", {"department": "Sales"}),
        ("happy", "ad_get_group_members", {"group": t["InGroup"]}),
        ("AD error", "ad_get_group_members", {"group": "no-such-group-zz"}),
        ("privileged read", "ad_get_group_members", {"group": "Domain Admins"}),
        ("happy", "ad_unlock_account", {"user": t["InTestUser"]}),
        ("AD denial", "ad_unlock_account", {"user": t["OutUser"]}),
        ("happy", "ad_add_group_member", {"group": t["InGroup"], "user": t["InTestUser"]}),
        ("AD denial", "ad_add_group_member", {"group": t["OutGroup"], "user": t["InTestUser"]}),
        ("refused", "ad_add_group_member", {"group": "Finance", "user": "x;whoami"}),
        ("happy (destructive)", "ad_disable_account", {"user": t["InTestUser"]}),
        ("AD denial", "ad_disable_account", {"user": t["OutUser"]}),
        ("happy", "admcp_my_tool_calls", {"limit": 20}),
    ]


async def main(targets: dict) -> None:
    params = StdioServerParameters(command=sys.executable, args=["-m", "admcp.server"], cwd=str(ROOT))
    with open(Path(targets.get("_errlog", ROOT / "run_tools.server.log")), "w", encoding="utf-8") as errlog:
        async with stdio_client(params, errlog=errlog) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()
                for label, name, args in calls(targets):
                    try:
                        res = await session.call_tool(name, args)
                        text = " ".join(getattr(c, "text", "") for c in res.content)
                        flag = getattr(res, "isError", getattr(res, "is_error", None))
                    except Exception as exc:  # a protocol error: keep going, the report shows it
                        text, flag = f"CLIENT EXCEPTION {type(exc).__name__}: {exc}", "exception"
                    print(f"--- {label}: {name} {json.dumps(args)} isError={flag}")
                    print(text[:1200])


if __name__ == "__main__":
    path = Path(sys.argv[1])
    t = json.loads(path.read_text(encoding="utf-8-sig"))
    t["_errlog"] = str(path.with_name("run_tools.server.log"))
    asyncio.run(main(t))
