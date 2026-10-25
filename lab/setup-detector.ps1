# lab/setup-detector.ps1 (Phase 6.1): install the detector on DC01. Elevated, on DC01. Idempotent.
#  - event source admcp-detector (Application log)
#  - failure auditing for Directory Service Access IN THE DC AUDIT GPO, and Everyone/WriteProperty FAILURE audit rules on
#    _LABTEST and _ADMINS, so a denied write by the agent leaves a 4662 failure for D5 (AD records nothing for a refused
#    write without a failure SACL on the object)
#  - scheduled task "admcp-detector": every 5 minutes as SYSTEM, C:\Lab\detector.ps1
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory, GroupPolicy
$dn = (Get-ADDomain).DistinguishedName

if (-not [System.Diagnostics.EventLog]::SourceExists('admcp-detector')) { New-EventLog -LogName Application -Source 'admcp-detector' }
"event source admcp-detector: registered"

# F-05 (25 Oct): a local `auditpol /set` does not stick on a DC whose GPO defines advanced audit policy: every subcategory
# the GPO leaves out is reset to No Auditing at the next refresh (0 events 4662 in two days). So the setting goes into
# the audit GPO's audit.csv, with the GPO version bumped in GPT.INI and in AD so the DC re-applies it.
$gpo = Get-GPO -Name 'Audit - Directory and Account Changes'
$root = "$env:SystemRoot\SYSVOL\domain\Policies\{$($gpo.Id)}"
$csv = "$root\Machine\Microsoft\Windows NT\Audit\audit.csv"
$raw = [IO.File]::ReadAllBytes($csv)
$enc = if ($raw.Length -ge 2 -and $raw[0] -eq 0xFF -and $raw[1] -eq 0xFE) { [Text.Encoding]::Unicode }
       elseif ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) { New-Object Text.UTF8Encoding($true) }
       else { New-Object Text.UTF8Encoding($false) }   # keep the file's own encoding and BOM
$text = [IO.File]::ReadAllText($csv)
if ($text -notmatch '0cce923b-69ae-11d9-bed3-505054503030') {
    $sample = ($text -split "`r?`n" | Where-Object { $_ -match ',System,' } | Select-Object -First 1)
    $machine = ($sample -split ',')[0]
    $line = "$machine,System,Audit Directory Service Access,{0cce923b-69ae-11d9-bed3-505054503030},Failure,,2"
    [IO.File]::WriteAllText($csv, $text.TrimEnd("`r", "`n") + "`r`n" + $line + "`r`n", $enc)
    "audit GPO: Directory Service Access (Failure) line added to audit.csv"
} else { "audit GPO: Directory Service Access already in audit.csv" }
gpupdate /target:computer /force | Out-Null
$dsa = "$(auditpol /get /subcategory:"Directory Service Access" | Select-String 'Directory Service Access')"
if ($dsa -notmatch 'Failure') {
    # the DC only re-reads a GPO whose version moved: bump the computer version in GPT.INI and in AD (they must match)
    $ini = "$root\GPT.INI"
    $lines = Get-Content $ini
    $v = [int](($lines | Where-Object { $_ -match '^Version=' } | Select-Object -First 1) -replace 'Version=', '') + 1
    $lines -replace '^Version=\d+', "Version=$v" | Set-Content $ini -Encoding ASCII
    Set-ADObject "CN={$($gpo.Id)},CN=Policies,CN=System,$dn" -Replace @{ versionNumber = $v }
    gpupdate /target:computer /force | Out-Null
    "audit GPO: version bumped to $v and re-applied"
}
"audit policy now: " + ((auditpol /get /subcategory:"Directory Service Access","Directory Service Changes" | Select-String 'Directory Service') -join ' | ')

# typed enum arguments: plain strings hit two constructor overloads ("ambiguous overloads", found 22 Oct)
$everyone = New-Object System.Security.Principal.SecurityIdentifier('S-1-1-0')
$rule = New-Object System.DirectoryServices.ActiveDirectoryAuditRule(
    $everyone,
    [System.DirectoryServices.ActiveDirectoryRights]::WriteProperty,
    [System.Security.AccessControl.AuditFlags]::Failure,
    [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All)
foreach ($ou in "OU=_LABTEST,$dn", "OU=_ADMINS,$dn") {
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ou'")) { "skip $ou (missing)"; continue }
    $acl = Get-Acl -Path "AD:$ou" -Audit
    $has = $acl.GetAuditRules($true, $false, [System.Security.Principal.SecurityIdentifier]) |
        Where-Object { $_.IdentityReference -eq $everyone -and $_.AuditFlags -eq 'Failure' -and ($_.ActiveDirectoryRights -band 'WriteProperty') }
    if (-not $has) { $acl.AddAuditRule($rule); Set-Acl -Path "AD:$ou" -AclObject $acl; "failure audit rule added on $ou" } else { "failure audit rule already on $ou" }
}

# F-06 (25 Oct): D4 was blind. The domain root's default success SACL audits writes on OU objects only (its inherited
# object type is organizationalUnit), and only _USERS and Groups carry their own Everyone rule, so a write by the agent
# anywhere else left no 5136. One rule at the root for the agent's group audits every write it makes, anywhere,
# succeeded or refused, without auditing anyone else.
$aiops = (Get-ADGroup 'AI-Operators').SID
$agentRule = New-Object System.DirectoryServices.ActiveDirectoryAuditRule(
    $aiops,
    [System.DirectoryServices.ActiveDirectoryRights]'WriteProperty, CreateChild, DeleteChild, Delete, WriteDacl, WriteOwner',
    [System.Security.AccessControl.AuditFlags]'Success, Failure',
    [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All)
$acl = Get-Acl -Path "AD:$dn" -Audit
if (-not ($acl.GetAuditRules($true, $false, [System.Security.Principal.SecurityIdentifier]) | Where-Object { $_.IdentityReference -eq $aiops })) {
    $acl.AddAuditRule($agentRule); Set-Acl -Path "AD:$dn" -AclObject $acl; "agent audit rule (AI-Operators, success + failure) added at the domain root"
} else { "agent audit rule already at the domain root" }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\Lab\detector.ps1'
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName 'admcp-detector' -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
"scheduled task admcp-detector: " + (Get-ScheduledTask -TaskName 'admcp-detector').State
