# PhasedSolutionPlan.md: AD Agent Lab

The living plan. SolutionDesign.md (v1.0) says *what* and *why*; this file says *what's next* and *what's done*.
Update it at the end of every session (closing prompt). Tick a task only when its check has passed.

## Session prompts

**Start of a session**

```
Read PhasedSolutionPlan.md, SolutionDesign.md and the last ten commits (git log -10).
Tell me: (1) the phase and task we're on, (2) what the last session finished, (3) what's next.
```

**Before each task (planning)**

```
Read this repo, SolutionDesign.md and PhasedSolutionPlan.md, then plan <task>. Before any code:
1. Break it into steps and say which can run independently.
2. List decisions with a real trade-off that need me (skip the ones with a clear winner), and any ambiguity in the docs.
3. Say how it will be tested on CLIENT01: a happy path and a denial path, both visible in DC01's Security log.
4. Review the plan critically yourself, then adjust it.
Don't start until I approve.
```

**End of a session (closing)**

```
Summarise what we did. Then: update PhasedSolutionPlan.md (tasks, progress log, decisions), list open items for me,
run tests\check_server.py, and commit.
```

If a session goes wrong: start a new one with the start prompt, say what broke, read `git log` / `git diff`, and
`git stash` broken half-work before resuming. In the lab, restore the latest checkpoint.

## Phases

### Phase 0: Lab prep (Ken at the laptop, no code)

- [ ] 0.1 Checkpoint DC01 and CLIENT01: `pre-agent`
- [ ] 0.2 Host: `Enable-VMIntegrationService -VMName CLIENT01 -Name "Guest Service Interface"` (for `Copy-VMFile`, D15)
- [ ] 0.3 DC01: GPO "Audit - Directory and Account Changes" on Domain Controllers. Advanced Audit Policy: DS Access →
      Directory Service Changes; Account Management → Security Group Management, User Account Management; Success +
      Failure. Prove it: a test group change shows 4728 and 5136 (add SACLs on `_USERS` / `Groups` if 5136 is missing)
- [ ] 0.4 New OU `_AGENTS`; group `AI-Operators` (in `Groups`); user `ai-operator` (in `_AGENTS`, member of
      `AI-Operators` only). Kept out of `_USERS` so the agent's own rights never cover its own account
- [ ] 0.5 CLIENT01: RSAT Active Directory + Group Policy Management (`Add-WindowsCapability`), Python 3.12+, Claude Code
- [ ] 0.6 Copy the repo to CLIENT01, make the venv, `tests\check_server.py` prints ok; Claude Code started in
      `operator\` as `ai-operator` lists 0 `admcp` tools
- [ ] 0.7 Checkpoint `pre-build`

### Phase 1: Solution design ✅ 21 Oct 2026

- [x] 1.1 SolutionDesign.md v0.1: D1–D4 agreed
- [x] 1.2 Q1–Q10 resolved as D5–D14; D15 (dev on host, `Copy-VMFile`, separate operator workspace); v1.0

### Phase 2: Scaffolding ✅ 21 Oct 2026

- [x] 2.1 Private repo `kenmwara/active-directory-ai-agent`, cloned at `cyber-range\public\active-directory-ai-agent`
- [x] 2.2 CLAUDE.md, this plan, FINDINGS.md, README.md, .gitignore
- [x] 2.3 Empty `admcp` server (SDK `mcp==2.3.0`, `MCPServer`, stdio) + `tests\check_server.py`: prints
      "0 tools" on the host; mutation-tested (an extra tool makes it fail)

### Phase 3: Read-only tools

- [ ] 3.1 Shared runner (JSON on stdin → fixed `.ps1` → JSON out, errors verbatim, 200-row cap) + call logger (JSON lines + Application event log, source `admcp`)
- [ ] 3.2 `ad_whoami`
- [ ] 3.3 `admcp_my_tool_calls`
- [ ] 3.4 `ad_search_users`
- [ ] 3.5 `ad_get_group_members`
- [ ] 3.6 `ad_list_locked_accounts`
- [ ] 3.7 `gpo_list`
- [ ] 3.8 `gpo_get_report`
- [ ] 3.9 `fs_get_acl` (path allowlist `\\DC01\Finance`)
- [ ] 3.10 `gpo_get_result_for_user`: done when it prints "Finance Drive Map, Filtering: Denied (Security)" for an HR user

### Phase 4: Delegation

- [ ] 4.1 `lab\setup-lab.ps1` (delegation section) grants `AI-Operators` exactly the rights in SolutionDesign §5, on the OUs in D6–D8
- [ ] 4.2 Delegation matrix: each right works inside its scope and fails one step outside it, AD's error word for word
- [ ] 4.3 Verify the move rights and the RSoP right in practice; update SolutionDesign §5 if reality differs

### Phase 5: Change and destructive tools

- [ ] 5.1 `ad_unlock_account`
- [ ] 5.2 `ad_add_group_member`
- [ ] 5.3 `ad_move_object` (`_USERS\IT` / `\Finance` / `\HR` only)
- [ ] 5.4 `gpo_link` (`Workstations` + the three department OUs only)
- [ ] 5.5 `ad_disable_account`
- [ ] 5.6 `ad_remove_group_member`
- [ ] 5.7 `gpo_set_security_filter` ("Finance Drive Map" only)
- [ ] 5.8 `operator\.mcp.json` + `operator\.claude\settings.json`: allow the tools, ask before the three destructive ones, deny shell and file writes; prove each rule once

### Phase 6: Detections

- [ ] 6.1 Detector script + 5-minute scheduled task on DC01 (alerts file + event log)
- [ ] 6.2 The five detections in SolutionDesign §9.4, each proven by a staged event

### Phase 7: Red-team campaign (v1, no policy in the server)

- [ ] 7.1 Checkpoint `pre-campaign`; stage the test data (locked accounts, planted instructions I-1 to I-5)
- [ ] 7.2 Run D-1 to D-3, I-1 to I-5, B-1 and B-2, A-1 to A-4, S-1 and S-2; every outcome in FINDINGS.md
- [ ] 7.3 Every miss by the detector gets a new rule, proven, then the test is re-run

### Phase 8: Fix, v2 and comparison

- [ ] 8.1 Fix every open finding and re-test it
- [ ] 8.2 v2: in-server limits (per-session change cap, refuse privileged groups); re-run the whole campaign; compare v1 and v2 (D9)
- [ ] 8.3 Re-run I-1 to I-5 on a smaller model and compare (D12)

### Phase 9: Publish

- [ ] 9.1 README rewritten for the public, screenshots, the findings summary; scrub check (no passwords, no LAPS output, no tokens)
- [ ] 9.2 Repo public (D14); added to the cyber-range README index and the portfolio
- [ ] 9.3 The Range post first, then LinkedIn (hook image); send it to Raymond Gonsalves, tag Josh Madakor

## Deadlines that matter

| Date | Why |
|---|---|
| ≈14 Jan 2027 | CLIENT01's Windows 11 evaluation expires: Phases 0–8 before then |
| ≈14 Apr 2027 | DC01's Server 2025 evaluation expires |

## Progress log

| Date | Session |
|---|---|
| 21 Oct 2026 | Phase 1: SolutionDesign v0.1 → v1.0 (D1–D15). Phase 2: repo, CLAUDE.md, this plan, FINDINGS.md, empty server + stdio check (0 tools, mutation-tested). Next: Phase 0 at the laptop, then Phase 3 |
