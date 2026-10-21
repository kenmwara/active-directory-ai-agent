"""admcp server entry point (stdio).

Tools arrive in Phase 3 (PhasedSolutionPlan.md). Each tool runs one fixed PowerShell script from scripts/,
passes its arguments as JSON on stdin, and appends one line to the call log.
"""
from mcp.server.mcpserver import MCPServer

server = MCPServer(name="admcp")


def main() -> None:
    server.run()  # stdio: Claude Code launches this process and talks over stdin/stdout


if __name__ == "__main__":
    main()
