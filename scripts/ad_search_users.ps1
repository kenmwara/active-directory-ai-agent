# ad_search_users: users under OU=_USERS by name, department and state. Read-only. JSON in on stdin, JSON out.
# The script validates again (CLAUDE.md rule 4): the name pattern has no quotes, so it cannot break out of the filter.
# Errors go to stderr word for word with exit 1 (runner.py passes them through). SolutionDesign.md section 5.2.
$ErrorActionPreference = "Stop"
try {
    $a = [Console]::In.ReadToEnd() | ConvertFrom-Json
    Import-Module ActiveDirectory -ErrorAction Stop
    $base = "OU=_USERS," + (Get-ADDomain).DistinguishedName
    if ($a.department) {
        if ("$($a.department)" -notmatch '^(IT|Finance|HR)$') { throw "department must be IT, Finance or HR" }
        $base = "OU=$($a.department),$base"
    }
    $filter = "*"
    if ($a.name) {
        if ("$($a.name)" -notmatch '^[A-Za-z0-9 ._*-]{1,64}$') { throw "name has characters that are not allowed" }
        $filter = "Name -like '*$($a.name)*' -or SamAccountName -like '*$($a.name)*'"
    }
    $users = Get-ADUser -SearchBase $base -Filter $filter -Properties LockedOut, LastLogonDate, Description -ResultSetSize 1000
    if ($a.enabled_only) { $users = $users | Where-Object { $_.Enabled } }
    if ($a.locked_only) { $users = $users | Where-Object { $_.LockedOut } }
    $rows = @(foreach ($u in $users) {
        $last = $null
        if ($u.LastLogonDate) { $last = $u.LastLogonDate.ToString("o") }
        [pscustomobject]@{
            name        = $u.Name
            sam         = $u.SamAccountName
            ou          = $u.DistinguishedName -replace '^CN=(?:\\,|[^,])+,', ''
            enabled     = [bool]$u.Enabled
            locked      = [bool]$u.LockedOut
            lastLogon   = $last
            description = $u.Description
        }
    })
    [pscustomobject]@{ count = $rows.Count; rows = $rows } | ConvertTo-Json -Depth 5
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
