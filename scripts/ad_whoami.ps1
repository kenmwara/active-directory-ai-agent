# ad_whoami: the account the server runs as, its groups, and the OUs where AI-Operators has delegated rights.
# Read-only. Reads (and ignores) a JSON object on stdin so every tool has the same interface. Errors go to stderr,
# word for word, with a non-zero exit (runner.py returns them unchanged). SolutionDesign.md section 5.1.
$ErrorActionPreference = "Stop"
try {
    [void][Console]::In.ReadToEnd()
    Import-Module ActiveDirectory -ErrorAction Stop
    $base = (Get-ADDomain).DistinguishedName
    $me = Get-ADUser -Identity $env:USERNAME -Properties MemberOf, DistinguishedName
    $groups = @()
    foreach ($g in $me.MemberOf) { $groups += (Get-ADGroup -Identity $g).Name }

    # Which of the candidate OUs carry an ACE for AI-Operators (the delegated-rights picture, best effort).
    $candidates = @(
        "OU=IT,OU=_USERS,$base", "OU=Finance,OU=_USERS,$base", "OU=HR,OU=_USERS,$base",
        "OU=_USERS,$base", "OU=Groups,$base"
    )
    $delegated = @()
    foreach ($ou in $candidates) {
        try {
            $acl = Get-Acl -Path ("AD:" + $ou)
            if ($acl.Access | Where-Object { "$($_.IdentityReference)" -like "*AI-Operators*" }) { $delegated += $ou }
        } catch { }
    }

    $out = [ordered]@{
        account           = "$env:USERDOMAIN\$env:USERNAME"
        sam               = $me.SamAccountName
        distinguishedName = $me.DistinguishedName
        groups            = $groups
        delegatedOUs      = $delegated
    }
    $out | ConvertTo-Json -Depth 5
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
