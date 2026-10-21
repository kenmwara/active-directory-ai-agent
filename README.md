# Active Directory AI Agent

An MCP server that lets an AI agent work in my Active Directory home lab, built so I can attack it.

The agent gets real tools for a real domain: search users, read group membership and Group Policy results, unlock
accounts, change groups, link and scope GPOs. Then I try to trick it, directly and through instructions hidden in the
directory data it reads, and record which layer stops it: AD's own permissions, a human confirmation, or a detection
on the domain controller.

**Status:** in build (private until the test campaign is done).

| Document | What it holds |
|---|---|
| [SolutionDesign.md](SolutionDesign.md) | The design: architecture, every tool and the right it needs, risks, the test plan |
| [PhasedSolutionPlan.md](PhasedSolutionPlan.md) | The phased plan and progress |
| [FINDINGS.md](FINDINGS.md) | The red-team findings |
| [CLAUDE.md](CLAUDE.md) | The rules for the coding agent |

The lab itself (Windows Server 2025 domain controller + Windows 11 client on Hyper-V) is documented in
[active-directory-lab](https://github.com/kenmwara/active-directory-lab). The build process (design document, CLAUDE.md,
phased plan) follows Josh Madakor's agentic coding guide.
