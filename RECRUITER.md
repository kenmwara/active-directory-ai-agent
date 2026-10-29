# Securing an AI Agent in Active Directory: Recruiter Brief

A two-minute overview. Full technical detail: [README.md](README.md).

---

## Summary

Companies are starting to give AI helpers real power over staff accounts: unlocking them, changing who belongs to
which group, switching accounts off. A helper with that power can be tricked into doing an attacker's work, either by a
bad request or by instructions hidden in something it reads.

This project gave one such helper a limited set of rights in a working Active Directory network (the system that holds
a company's accounts), then tried 13 ways to make it misbehave: hidden commands, grabs for admin power, oversized changes
and attempts to get around its limits. The question was simple: **when the AI is fooled, what stops it?**

---

## Approach

The design doesn't count on the AI saying no, because the AI is exactly what an attacker tries to fool. Three safety
layers hold however the AI behaves:

- **Limited rights.** The helper's account can only touch two areas of the directory, and Active Directory enforces it.
- **A person approves.** The one change that can't be undone (switching an account off) waits for a person to say yes.
- **Its own record.** The server logs every change and raises an alert on anything suspicious, using its own log, not the AI's word.

---

## Results

- **Hidden commands never worked.** Three attempts, including a disguised "make me admin" command, were treated as plain
  text. Nothing happened.
- **Changes outside its area were refused** by Active Directory, and the matching alert went off.
- **One gap is still open: too many changes at once.** Requests to unlock 51 accounts and to add 200 users were within
  its rights, so they went through. Alerts caught both but didn't stop them. Version 2 adds a limit per session.
- **Eight setup weaknesses** were found, fixed and re-tested before the testing began.

---

## Skills demonstrated

- **AI agent security:** prompt-injection and tool-misuse testing mapped to the OWASP Top 10 for LLM Applications, the
  OWASP Top 10 for Agentic Applications and MITRE ATLAS
- **Identity security:** least-privilege delegation in Active Directory, advanced audit policy, detection rules
  validated with staged events
- **Detection engineering:** five detection rules on the domain controller, each verified before use
- **Secure design:** no password handling, no shell access, and agent text never reaches a command line
- **Documentation:** design document, phased plan and a findings log covering every test

**Stack:** Windows Server 2025, Active Directory, PowerShell, Python, Model Context Protocol (MCP), Claude Code,
Hyper-V.

---

## Related work

The environment is the [Active Directory lab](https://github.com/kenmwara/active-directory-lab): a domain controller
and a domain-joined Windows 11 client on Hyper-V, with 999 users and five Group Policies.
