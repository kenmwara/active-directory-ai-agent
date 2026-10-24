# lab/test-delegation.ps1 (Phase 4.2): each v1 right must work inside its scope and fail one step outside it.
# Run on CLIENT01 as KENLAB\ai-operator, AFTER `setup-lab.ps1 -Part Delegation`. Prints AD's error word for word.
# Every allowed change is undone at once. An out-of-scope "allowed" is a FINDING (and is undone too).
param(
    [Parameter(Mandatory)][string]$InUser,    # a test user inside OU=_USERS
    [Parameter(Mandatory)][string]$OutUser,   # a NON-admin test user outside OU=_USERS (never an admin account)
    [Parameter(Mandatory)][string]$InGroup,   # a group inside OU=Groups
    [Parameter(Mandatory)][string]$OutGroup,  # a non-privileged group outside OU=Groups
    [Parameter(Mandatory)][string]$Member     # the user added, then removed, in the member tests
)
$ErrorActionPreference = "Stop"
Import-Module ActiveDirectory

function Test-Right([string]$Name, [string]$Expect, [scriptblock]$Do, [scriptblock]$Undo) {
    try { & $Do; $got = "allowed" } catch { $got = "denied: $($_.Exception.Message)" }
    if ($got -eq "allowed" -and $Undo) {
        try { & $Undo } catch { $got += " (UNDO FAILED: $($_.Exception.Message))" }
    }
    $verdict = if ($got.StartsWith($Expect)) { "PASS" } else { "FINDING" }
    [pscustomobject]@{ test = $Name; expected = $Expect; result = $got; verdict = $verdict }
}

@(
    Test-Right "lockoutTime, in _USERS"     "allowed" { Unlock-ADAccount $InUser }
    Test-Right "lockoutTime, outside"       "denied"  { Unlock-ADAccount $OutUser }
    Test-Right "disable, in _USERS"         "allowed" { Disable-ADAccount $InUser } { Enable-ADAccount $InUser }
    Test-Right "disable, outside"           "denied"  { Disable-ADAccount $OutUser } { Enable-ADAccount $OutUser }
    Test-Right "member, group in Groups"    "allowed" { Add-ADGroupMember $InGroup -Members $Member } { Remove-ADGroupMember $InGroup -Members $Member -Confirm:$false }
    Test-Right "member, group outside"      "denied"  { Add-ADGroupMember $OutGroup -Members $Member } { Remove-ADGroupMember $OutGroup -Members $Member -Confirm:$false }
) | Format-Table -AutoSize -Wrap
