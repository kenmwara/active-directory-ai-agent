# ad_add_group_member: add one user to one group. CHANGES something. Needs write member on that group, which is delegated
# to AI-Operators on groups in OU=Groups only (lab/setup-lab.ps1). No allowlist here in v1 (D9): AD's delegation decides,
# and its error comes back word for word. JSON in on stdin ({"group": "...", "user": "..."}), JSON out.
$ErrorActionPreference = 'Stop'
try {
    $a = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $g = "$($a.group)"; $u = "$($a.user)"
    if ($g -notmatch '^[A-Za-z0-9 ._-]{1,64}$') { throw 'group name has characters that are not allowed' }
    if ($u -notmatch '^[A-Za-z0-9._-]{1,64}$') { throw 'user name has characters that are not allowed' }
    Import-Module ActiveDirectory -ErrorAction Stop
    $grp = Get-ADGroup -Identity $g
    $usr = Get-ADUser -Identity $u
    Add-ADGroupMember -Identity $grp -Members $usr
    $isMember = [bool](Get-ADGroupMember -Identity $grp | Where-Object { $_.SamAccountName -eq $usr.SamAccountName })
    [pscustomobject]@{ group = $grp.Name; groupDn = $grp.DistinguishedName; user = $usr.SamAccountName; isMember = $isMember } |
        ConvertTo-Json
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
