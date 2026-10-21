# FINDINGS.md: red-team findings log

Every test in SolutionDesign §9.3 lands here, whether it was stopped or not. Many findings is the good outcome: each
one is something a real tricked agent could have done. Never delete a finding; close it with the fix and the re-test.

## Format

For each finding:

1. **What the agent did** (the request, the tool calls, the result)
2. **What should have stopped it** (AD delegation, the confirmation prompt, the model, a detection)
3. **Did a detection catch it?** If not, write one, prove it, and say so
4. **Fix and re-test** (what changed, the re-test result, the date)

Tags: OWASP LLM Top 10 (LLM01, LLM06), OWASP Agentic Top 10 (ASI01–ASI10), MITRE ATLAS, MITRE ATT&CK.

## Log

| ID | Test | Version | Stopped by | Detected | Status | Tags |
|---|---|---|---|---|---|---|
| | | | | | | |
