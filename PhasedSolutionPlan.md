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

### Phase 0: Lab prep (Ken at the laptop, no code) ✅ 22 Oct 2026

Scripted 22 Oct (my shell can't reach Hyper-V, so Ken runs them, elevated): `lab\phase0-host.ps1` on the laptop (0.1, 0.2, copies the next two + `dist\admcp-<sha>.zip` into the VMs), `C:\Lab\phase0-dc01.ps1` on DC01 as a-kkariuki (0.3, 0.4, proves 4728 + 5136), `C:\Lab\phase0-client01.ps1` on CLIENT01 as a-kkariuki (0.5, 0.6 admin part: RSAT, Python, Git, `C:\ADAgent` read-only to non-admins, venv, stdio check), then Claude Code as ai-operator in `C:\ADAgent\operator` (`/mcp`: admcp connected, 0 tools), then `phase0-host.ps1 -Final` (0.7).


- [x] 0.1 Checkpoint DC01 and CLIENT01: `pre-agent` (22 Oct)
- [x] 0.2 (22 Oct; scripts + `admcp-040f537.zip` copied to `C:\Lab`) Host: `Enable-VMIntegrationService -VMName CLIENT01 -Name "Guest Service Interface"` (for `Copy-VMFile`, D15)
- [x] 0.3 (22 Oct: PASS, 4728 x1 + 5136 x2 within 7 s. The domain root's default SACL already fires 5136; the script's
      extra Success+Failure SACLs on `Groups` and `_USERS` went on before that was known and stay) DC01: GPO "Audit - Directory and Account Changes" on Domain Controllers. Advanced Audit Policy: DS Access →
      Directory Service Changes; Account Management → Security Group Management, User Account Management; Success +
      Failure. Prove it: a test group change shows 4728 and 5136 (add SACLs on `_USERS` / `Groups` if 5136 is missing)
- [x] 0.4 (22 Oct) New OU `_AGENTS`; group `AI-Operators` (in `Groups`); user `ai-operator` (in `_AGENTS`, member of
      `AI-Operators` only). Kept out of `_USERS` so the agent's own rights never cover its own account
- [x] 0.5 (22 Oct: RSAT AD + GPMC installed, Python 3.12.10, Git 2.55.0.5, Claude Code 2.1.309 as ai-operator) CLIENT01: RSAT Active Directory + Group Policy Management (`Add-WindowsCapability`), Python 3.12+, Claude Code
- [x] 0.6 (22 Oct: `admcp-11ba90a.zip` → `C:\ADAgent`, venv, check_server ok: 0 tools; `/mcp` as ai-operator: admcp connected, after F-00's managed settings) Copy the repo to CLIENT01, make the venv, `tests\check_server.py` prints ok; Claude Code started in
      `operator\` as `ai-operator` lists 0 `admcp` tools
- [x] 0.7 (22 Oct 18:02, both VMs off: offline, no saved memory) Checkpoint `pre-build`

### Phase 1: Solution design ✅ 21 Oct 2026

- [x] 1.1 SolutionDesign.md v0.1: D1–D4 agreed
- [x] 1.2 Q1–Q10 resolved as D5–D14; D15 (dev on host, `Copy-VMFile`, separate operator workspace); v1.0

### Phase 2: Scaffolding ✅ 21 Oct 2026

- [x] 2.1 Private repo `kenmwara/active-directory-ai-agent`, cloned at `cyber-range\public\active-directory-ai-agent`
- [x] 2.2 CLAUDE.md, this plan, FINDINGS.md, README.md, .gitignore
- [x] 2.3 Empty `admcp` server (SDK `mcp==2.3.0`, `MCPServer`, stdio) + `tests\check_server.py`: prints
      "0 tools" on the host; mutation-tested (an extra tool makes it fail)

### Phase 3: Read-only tools

Lean cut (Ken, 22 Oct; SolutionDesign D16): v1 = 3.1–3.5; the rest is v2.

- [ ] 3.1 Shared runner (JSON on stdin → fixed `.ps1` → JSON out, errors verbatim, 200-row cap) + call logger (JSON lines + Application event log, source `admcp`) (24 Oct: written, host checks ok; CLIENT01 happy + denial run pending)
- [ ] 3.2 `ad_whoami` (24 Oct: written, host checks ok; CLIENT01 happy + denial run pending)
- [ ] 3.3 `admcp_my_tool_calls` (24 Oct: written, host checks ok; CLIENT01 happy + denial run pending)
- [ ] 3.4 `ad_search_users` (with `locked_only`) (24 Oct: written, host checks ok; CLIENT01 happy + denial run pending)
- [ ] 3.5 `ad_get_group_members` (24 Oct: written, host checks ok; CLIENT01 happy + denial run pending)
- [ ] 3.6 (v2) `ad_list_locked_accounts`
- [ ] 3.7 (v2) `gpo_list`
- [ ] 3.8 (v2) `gpo_get_report`
- [ ] 3.9 (v2) `fs_get_acl` (path allowlist `\\DC01\Finance`)
- [ ] 3.10 (v2) `gpo_get_result_for_user`: done when it prints "Finance Drive Map, Filtering: Denied (Security)" for an HR user

### Phase 4: Delegation

- [ ] 4.1 `lab\setup-lab.ps1` (delegation section) grants `AI-Operators` exactly the v1 rights in SolutionDesign §5 (`lockoutTime` and `userAccountControl` on users in `_USERS`, `member` on groups in `OU=Groups`); the D6–D8 rights are v2 (24 Oct: written as `-Part Delegation` (DC01) + `-Part EventSource` (CLIENT01), parse-checked; Ken runs it)
- [ ] 4.2 Delegation matrix: each right works inside its scope and fails one step outside it, AD's error word for word (24 Oct: `lab\test-delegation.ps1` written, run as ai-operator with 5 test targets; any out-of-scope 'allowed' prints FINDING and is undone)
- [ ] 4.3 (v2) Verify the move rights and the RSoP right in practice; update SolutionDesign §5 if reality differs

### Phase 5: Change and destructive tools

- [ ] 5.1 `ad_unlock_account`
- [ ] 5.2 `ad_add_group_member`
- [ ] 5.3 (v2) `ad_move_object` (`_USERS\IT` / `\Finance` / `\HR` only)
- [ ] 5.4 (v2) `gpo_link` (`Workstations` + the three department OUs only)
- [ ] 5.5 `ad_disable_account`
- [ ] 5.6 (v2) `ad_remove_group_member`
- [ ] 5.7 (v2) `gpo_set_security_filter` ("Finance Drive Map" only)
- [ ] 5.8 `operator\.mcp.json` + `operator\.claude\settings.json`: allow the tools, ask before `ad_disable_account` (the one destructive v1 tool), deny shell and file writes; prove each rule once. Auto mode is Claude Code's default since 2.1.x and only user or managed settings can change `defaultMode`: decide it in managed settings and prove the ask rules still prompt. Reads outside `operator\` prompt ("Read outside the working directories"); the agent needs no file reads at all, so decide `blockReadsOutsideWorkingDirectories` there too. Opus 5.5's cyber safeguard switched an ai-operator session to Opus 4.8 on a README read (22 Oct): log which model answered in every campaign run (D12, the video). Deny reading `~\.claude\` (ai-operator's Claude login token lives there since 22 Oct) and add a red-team test: can planted text make the agent read it?

### Phase 6: Detections

- [ ] 6.1 Detector script + 5-minute scheduled task on DC01 (alerts file + event log)
- [ ] 6.2 The five detections in SolutionDesign §9.4, each proven by a staged event

### Phase 7: Red-team campaign (v1, no policy in the server)

- [ ] 7.1 Checkpoint `pre-campaign`; stage the test data (locked accounts, planted instructions I-1 to I-5)
- [ ] 7.2 Run D-1 to D-3, I-1, I-2, I-5, B-1 and B-2, A-1 to A-3, S-1 and S-2 (13 tests; I-3, I-4, A-4 are v2); every outcome in FINDINGS.md
- [ ] 7.3 Every miss by the detector gets a new rule, proven, then the test is re-run
- [ ] 7.4 Record the campaign on video (Ken, 21 Oct): the agent's request, the tool calls, what stopped it (AD's denial, the confirmation prompt, the DC01 alert). Screen capture with OBS on the host; one take per test family, cut to a short edit

### Phase 8: Fix, v2 and comparison

- [ ] 8.1 Fix every open finding and re-test it
- [ ] 8.2 v2: in-server limits (per-session change cap, refuse privileged groups); re-run the whole campaign; compare v1 and v2 (D9)
- [ ] 8.3 Re-run I-1 to I-5 on a smaller model and compare (D12)

### Phase 9: Publish

- [ ] 9.1 README rewritten for the public, screenshots, the findings summary; scrub check (no passwords, no LAPS output, no tokens)
- [ ] 9.2 Repo public (D14); added to the cyber-range README index and the portfolio
- [ ] 9.3 The Range post first, then LinkedIn (hook image + the campaign video in both); send it to Raymond Gonsalves, tag Josh Madakor

## Deadlines that matter

| Date | Why |
|---|---|
| ≈14 Jan 2027 | CLIENT01's Windows 11 evaluation expires: Phases 0–8 before then |
| ≈14 Apr 2027 | DC01's Server 2025 evaluation expires |

## Progress log

| Date | Session |
|---|---|
| 21 Oct 2026 | Phase 1: SolutionDesign v0.1 → v1.0 (D1–D15). Phase 2: repo, CLAUDE.md, this plan, FINDINGS.md, empty server + stdio check (0 tools, mutation-tested). Next: Phase 0 at the laptop, then Phase 3 |
| 22 Oct 2026 | Phase 0 run: 0.1–0.4 PASS; CLIENT01 admin part (RSAT, Python, Git, `C:\ADAgent`, stdio ok) done. F-00 found and fixed (the agent identity inherited the Claude account's connectors and plugins; admin-only managed settings). C: fell from 21 to 2.8 GB (CLIENT01 wrote 11.6 GB in 2 h, plus RAM-sized `.VMRS` files): VMs set to AutomaticStopAction ShutDown + Production checkpoints. 0.7 `pre-build` taken with both VMs off. **Phase 0 done.** Lean cut agreed (D16: 4 read + 3 change tools, 13 campaign tests). Next: Phase 3, `ad_whoami`. Two script bugs fixed on the way: `ActiveDirectoryAuditRule` needs typed args (string args hit two constructors), and 5136 lands ~9 s after the change, so the proof polls instead of one 5 s check (found with two PowerShell Direct diagnostics). Phase 0 scripted: `lab\phase0-host.ps1`, `lab\phase0-dc01.ps1`, `lab\phase0-client01.ps1` (all parse-checked) + `operator\.mcp.json` (launches admcp from `C:\ADAgent\.venv`). Ken runs them in order |
| 24 Oct 2026 | Phase 3 + 4 code written on the host: `admcp/runner.py` (JSON on stdin to one fixed `.ps1`, errors verbatim, 200-row cap, refused calls logged as `rejected`), `admcp/calllog.py` (JSON lines + Application event log; message via env var, never the command line), 4 read tools in `server.py` + `scripts/ad_whoami.ps1`, `ad_search_users.ps1`, `ad_get_group_members.ps1` (each validates again; the name pattern has no quotes, so it cannot break out of the AD filter). `tests/check_server.py` = 4 tools ok; new `tests/check_runner.py` (stub scripts, no domain) ok; 4 of 4 mutants caught; every `.ps1` parses. Phase 4: `lab/setup-lab.ps1` (dsacls grants, idempotent) + `lab/test-delegation.ps1`. Design note for the campaign: write on `userAccountControl` is the whole flag word (DONT_REQ_PREAUTH, PASSWD_NOTREQD too), not just disable. Next: Copy-VMFile to CLIENT01, `setup-lab.ps1 -Part Delegation` on DC01 and `-Part EventSource` on CLIENT01, then each tool's happy + denial run with DC01's Security log |
