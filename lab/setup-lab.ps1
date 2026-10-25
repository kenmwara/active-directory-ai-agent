# lab/setup-lab.ps1 (Phase 4.1): the delegation that decides what the agent can change (SolutionDesign.md section 5).
#   -Part Delegation   on DC01, elevated: grant AI-Operators exactly the v1 write rights, nothing else
#   -Part EventSource  on CLIENT01, elevated: register the "admcp" Application event-log source (admcp/calllog.py)
# Idempotent. Never grants anything on _ADMINS, privileged groups, the Domain Controllers OU or the domain root.
#
# Known gap to test in the campaign: userAccountControl is the whole flag word. Write access to it lets the holder set
# any flag (DONT_REQ_PREAUTH, PASSWD_NOTREQD...), not only ACCOUNTDISABLE. ad_disable_account only disables, but a
# bypass path (S-1, Claude Code's own shell) holds the same right. Check what DC01's 4738 events show when it happens.
param([Parameter(Mandatory)][ValidateSet("Delegation", "EventSource")][string]$Part)
$ErrorActionPreference = "Stop"

if ($Part -eq "EventSource") {
    if (-not [System.Diagnostics.EventLog]::SourceExists("admcp")) { New-EventLog -LogName Application -Source "admcp" }
    Write-Output "admcp event source registered on $env:COMPUTERNAME"
    return
}

Import-Module ActiveDirectory
$domain = Get-ADDomain
$who = "$($domain.NetBIOSName)\AI-Operators"
# Groups is found by name, as phase0-dc01.ps1 does: it is not guaranteed to sit at the domain root
$groupsOU = @(Get-ADOrganizationalUnit -Filter "Name -eq 'Groups'")
if ($groupsOU.Count -ne 1) { throw "Expected exactly one OU named Groups, found $($groupsOU.Count)" }
$grants = @(
    @{ ou = "OU=_USERS,$($domain.DistinguishedName)"; right = "WP;lockoutTime;user" },         # ad_unlock_account
    @{ ou = "OU=_USERS,$($domain.DistinguishedName)"; right = "WP;userAccountControl;user" },  # ad_disable_account
    @{ ou = $groupsOU[0].DistinguishedName;           right = "WP;member;group" }              # ad_add_group_member
)
foreach ($g in $grants) {
    Get-ADOrganizationalUnit -Identity $g.ou | Out-Null   # stops here, loudly, if the OU is missing
    dsacls $g.ou /I:S /G "${who}:$($g.right)" | Out-Null   # /I:S = inherited by child objects of that class only
    if ($LASTEXITCODE -ne 0) { throw "dsacls failed ($LASTEXITCODE) granting $($g.right) on $($g.ou)" }
    Write-Output "granted $who $($g.right) on $($g.ou)"
}
