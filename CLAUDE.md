# CLAUDE.md: rules for agents working on this repo

This file is for the **coding** agent that builds `admcp`. The **operator** agent that uses the tools against the
domain runs from `operator\` under its own, much tighter settings (SolutionDesign.md D15).

## What this is

`admcp` is an MCP server that gives an AI agent tools for the KENLAB Active Directory lab (`ad.kenmwara.com`, DC01 +
CLIENT01 on a private Hyper-V switch). It exists to be attacked: the red-team campaign measures which layer stops a
tricked agent (AD delegation, a confirmation prompt, a detection on DC01). **SolutionDesign.md is the source of truth;
PhasedSolutionPlan.md is the living plan.** Read both before any task.

## Layout

| Path | Holds |
|---|---|
| `admcp/server.py` | The MCP server (SDK v2 `MCPServer`, stdio). Registers tools; no AD logic of its own |
| `admcp/` (later) | The PowerShell runner and the call logger, shared by every tool |
| `scripts/<tool>.ps1` | One fixed script per tool (created with the tool) |
| `lab/` | Lab setup run by Ken on DC01 / CLIENT01: delegation, audit policy, detector, test data |
| `operator/` | The operator workspace: `.mcp.json` + `.claude/settings.json` (deny shell, ask before destructive) |
| `tests/check_server.py` | Starts the server over stdio and checks the exact tool list |
| `FINDINGS.md` | The red-team findings log |

## How every tool is built (non-negotiable)

1. Name: `domain_verb_object` (`ad_unlock_account`, `gpo_get_report`).
2. The description says three things: what it does, the **exact AD right** it needs, and whether it is read-only,
   changes something, or is destructive.
3. The Python side validates the arguments, then runs
   `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts\<tool>.ps1` and sends the
   arguments as **one JSON object on stdin**. Agent text never goes on a command line, into `Invoke-Expression`, or
   into a script block.
4. The `.ps1` validates again (account names by pattern, DNs under an allowed base, paths under `\\DC01\Finance`),
   does one job with the ActiveDirectory or GroupPolicy module, and writes one JSON object to stdout.
5. AD errors go back **word for word** ("Access is denied" stays "Access is denied"). Never retry with other rights.
6. Results are capped at 200 rows and say when they were trimmed.
7. Every call appends one JSON line to the call log: timestamp, tool, arguments, caller, outcome, error text,
   duration, rows, trimmed.
8. Add the tool's name to `EXPECTED` in `tests/check_server.py` in the same commit.

## Never

- Password tools of any kind (reset, set, LAPS read), create/delete users, groups or GPOs, edits to GPO settings.
- Anything touching `_ADMINS`, privileged groups, the Domain Controllers OU, the domain root, the Default Domain
  Policy, AdminSDHolder or the schema.
- A tool that runs arbitrary PowerShell or commands.
- **Policy inside the server in v1** (D9): no caps, no allowlists beyond input validation. v2 adds them on purpose.
- Secrets in code, config, logs or commits. Lab passwords are never written down.
- Anything outside the AD lab (shared training tenants, third-party environments).

## Commands

```
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt
.venv\Scripts\python tests\check_server.py      # must print "ok"
```

PowerShell scripts run only on CLIENT01 (they need RSAT and the domain). The host cannot reach the lab network, so
code reaches CLIENT01 with `Copy-VMFile` (D15); run them there.

## Workflow

- Spec-driven process: start prompt → planning prompt → approve → build → closing prompt (PhasedSolutionPlan.md).
- **Commit after every task.** Messages say what changed and why.
- Run `tests\check_server.py` before every commit. A tool isn't done until it has a happy-path and a denial-path
  run on CLIENT01, both visible in DC01's Security log.
- Findings go in `FINDINGS.md` in the fixed format; never delete one, close it with the fix and the re-test.

## Git

Identity is per repo: `Ken Mwara <kenmwara@users.noreply.github.com>`. Branch: `main`. Never force-push.
The repo stays private until the campaign is done (D14).
