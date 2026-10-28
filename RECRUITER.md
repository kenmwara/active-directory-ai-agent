# Securing an Active Directory Agent: Recruiter Brief

A two-minute overview of what I built and why it matters. The full technical detail is in [README.md](README.md).

---

## What this project is

Companies are starting to give AI agents real permissions: unlock accounts, change group membership, disable users.
An agent like that can be talked into doing an attacker's work, either by a bad request or by instructions hidden in
the data it reads.

I built that agent on purpose. It runs with real rights in a live Active Directory domain (the identity system most
companies use), and then I attacked it with prompt injection and misuse to answer one question: **when the agent is
manipulated, which security control actually contains it?**

---

## Why this matters

Most AI security advice says "make the model refuse bad requests." The model is the one part an attacker is trying to
fool, so this project doesn't rely on it. The agent is boxed in by three controls that work even if the model is
tricked:

- **Permissions.** The agent's account can only touch two areas of the directory, and the directory itself enforces
  that.
- **A human approval.** The one action that can't be undone asks a person first.
- **Independent detection.** The domain controller logs every change and raises an alert on suspicious patterns,
  using its own records rather than the agent's.

---

## What I found

- **Hidden instructions didn't work.** Three injection attempts, including an encoded "make admin" command, were
  treated as data. The agent ran nothing.
- **Out-of-scope changes were stopped by the directory itself**, and the alert fired.
- **The open gap is volume.** When the agent was asked to unlock 51 accounts or add 200 users, it was allowed to, and
  the detections flagged it but didn't stop it. The next version adds a per-session limit.
- **Every finding is validated, mitigated and re-tested**, including 8 setup weaknesses found and fixed before the
  test campaign started.

---

## What it demonstrates

- **AI agent security:** prompt-injection and tool-misuse testing mapped to the OWASP Top 10 for LLM Applications, the
  OWASP Top 10 for Agentic Applications and MITRE ATLAS
- **Identity security:** least-privilege delegation in Active Directory, audit policy, and detection rules proven with
  staged events
- **Detection engineering:** five detection rules on the domain controller, each tested before it was trusted
- **Secure design:** the agent never handles passwords, has no shell, and its text never reaches a command line
- **Documented engineering:** a written design, a phased plan, and a findings log for every test

**Stack:** Windows Server 2025, Active Directory, PowerShell, Python, the Model Context Protocol (MCP), Claude Code,
Hyper-V.

---

## How it fits

This builds on my [Active Directory home lab](https://github.com/kenmwara/active-directory-lab): a domain controller
and a domain-joined Windows 11 client on Hyper-V, with 999 users and five Group Policies. The lab is the environment;
this project is the security test of an AI agent working inside it.
