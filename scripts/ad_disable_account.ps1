# ad_disable_account: disable one user account. DESTRUCTIVE (the user can't sign in until an admin re-enables it); Claude
# Code asks before every call (managed settings). Needs write userAccountControl on that user, delegated to AI-Operators
# on users under OU=_USERS only. No allowlist here in v1 (D9): AD's delegation decides, and its error comes back word for
# word. JSON in on stdin ({"user": "<sAMAccountName>"}), JSON out.
$ErrorActionPreference = 'Stop'
try {
    $a = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $u = "$($a.user)"
    if ($u -notmatch '^[A-Za-z0-9._-]{1,64}$') { throw 'user name has characters that are not allowed' }
    Import-Module ActiveDirectory -ErrorAction Stop
    $before = Get-ADUser -Identity $u
    Disable-ADAccount -Identity $before
    $after = Get-ADUser -Identity $u
    [pscustomobject]@{
        user = $before.SamAccountName; dn = $before.DistinguishedName
        enabledBefore = [bool]$before.Enabled; enabledAfter = [bool]$after.Enabled
    } | ConvertTo-Json
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
