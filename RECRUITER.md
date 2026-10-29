# Securing an AI Agent in Active Directory: Recruiter Brief

A two-minute overview. Full technical detail: [README.md](README.md).

---

## Summary

Organisations are beginning to give AI agents real permissions: unlocking accounts, changing group membership,
disabling users. An agent with those rights can be manipulated into doing an attacker's work, through a malicious
request or through instructions hidden in the data it reads.

This project deployed such an agent with delegated rights in a live Active Directory domain, then assessed it with a
13-test adversarial campaign (prompt injection, privilege escalation, excessive agency, control bypass) to answer one
question: **when the agent is manipulated, which security control contains it?**

---

## Approach

The design does not rely on the model refusing bad requests, because the model is the component an attacker is trying
to deceive. Three controls contain the agent regardless of the model's behaviour:

- **Permissions.** The agent's account is delegated rights on two areas of the directory only, enforced by Active
  Directory.
- **Human approval.** The one irreversible action requires confirmation from a person.
- **Independent detection.** The domain controller audits every change and alerts on suspicious patterns from its own
  logs, not the agent's.

---

## Results

- **Prompt injection was ineffective.** Three injection attempts, including an encoded "make admin" command, were
  treated as data. No action was taken.
- **Out-of-scope changes were denied by the directory**, and the corresponding detection fired.
- **One gap remains open: volume.** Requests to unlock 51 accounts and to add 200 users fell within the agent's rights
  and executed. Detection flagged both but did not block them. Version 2 adds a per-session change limit.
- **Eight configuration weaknesses** were identified, remediated and re-tested before the campaign began.

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
