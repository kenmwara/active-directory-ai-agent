# lab/setup-detector.ps1 (Phase 6.1): install the detector on DC01. Elevated, on DC01. Idempotent.
#  - event source admcp-detector (Application log)
#  - failure auditing for Directory Service Access, and Everyone/WriteProperty FAILURE audit rules on _LABTEST and
#    _ADMINS, so a denied write by the agent leaves a 4662 failure for D5 (AD records nothing for a refused write without
#    a failure SACL on the object)
#  - scheduled task "admcp-detector": every 5 minutes as SYSTEM, C:\Lab\detector.ps1
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
$dn = (Get-ADDomain).DistinguishedName

if (-not [System.Diagnostics.EventLog]::SourceExists('admcp-detector')) { New-EventLog -LogName Application -Source 'admcp-detector' }
"event source admcp-detector: registered"

auditpol /set /subcategory:"Directory Service Access" /failure:enable | Out-Null
auditpol /set /subcategory:"Directory Service Changes" /success:enable | Out-Null
"audit policy: " + ((auditpol /get /subcategory:"Directory Service Access","Directory Service Changes" | Select-String 'Directory Service') -join ' | ')

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

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\Lab\detector.ps1'
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName 'admcp-detector' -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
"scheduled task admcp-detector: " + (Get-ScheduledTask -TaskName 'admcp-detector').State
