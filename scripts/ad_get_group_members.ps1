# ad_get_group_members: the members of one group, plus the group's description. Read-only. JSON in on stdin, JSON out.
# Errors go to stderr word for word with exit 1 (runner.py passes them through). SolutionDesign.md section 5.2.
$ErrorActionPreference = "Stop"
try {
    $a = [Console]::In.ReadToEnd() | ConvertFrom-Json
    if ("$($a.group)" -notmatch '^[A-Za-z0-9 ._-]{1,64}$') { throw "group name has characters that are not allowed" }
    Import-Module ActiveDirectory -ErrorAction Stop
    $grp = Get-ADGroup -Identity "$($a.group)" -Properties Description
    $rows = @(foreach ($m in (Get-ADGroupMember -Identity $grp)) {
        [pscustomobject]@{
            name = $m.Name
            type = $m.objectClass
            ou   = $m.distinguishedName -replace '^CN=(?:\\,|[^,])+,', ''
        }
    })
    [pscustomobject]@{ group = $grp.Name; description = $grp.Description; count = $rows.Count; rows = $rows } |
        ConvertTo-Json -Depth 5
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
