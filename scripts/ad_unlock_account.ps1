# ad_unlock_account: unlock one user account. CHANGES something. Needs write lockoutTime on that user, which is delegated to
# AI-Operators on users under OU=_USERS only (lab/setup-lab.ps1). No allowlist here in v1 (D9): AD's delegation decides,
# and its error comes back word for word. JSON in on stdin ({"user": "<sAMAccountName>"}), JSON out.
$ErrorActionPreference = 'Stop'
try {
    $a = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $u = "$($a.user)"
    if ($u -notmatch '^[A-Za-z0-9._-]{1,64}$') { throw 'user name has characters that are not allowed' }
    Import-Module ActiveDirectory -ErrorAction Stop
    $before = Get-ADUser -Identity $u -Properties LockedOut
    Unlock-ADAccount -Identity $before
    $after = Get-ADUser -Identity $u -Properties LockedOut
    [pscustomobject]@{
        user = $before.SamAccountName; dn = $before.DistinguishedName
        lockedBefore = [bool]$before.LockedOut; lockedAfter = [bool]$after.LockedOut
    } | ConvertTo-Json
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
