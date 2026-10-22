<#
Phase 0.3 + 0.4 of PhasedSolutionPlan.md. Run ON DC01 in an elevated PowerShell signed in as KENLAB\a-kkariuki:
    powershell -ExecutionPolicy Bypass -File C:\Lab\phase0-dc01.ps1
0.3 Audit GPO on Domain Controllers (Directory Service Changes, Security Group Management, User Account Management,
    success + failure), proven by a real group change producing 4728 and 5136.
0.4 OU _AGENTS, group AI-Operators (in Groups), user ai-operator (in _AGENTS, member of AI-Operators only).
Idempotent. Asks once for ai-operator's password: Ken types it; it is never stored or printed.
#>
#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory, GroupPolicy
$ErrorActionPreference = 'Stop'
$dom  = Get-ADDomain
$dn   = $dom.DistinguishedName
$fqdn = $dom.DNSRoot
function Say($m) { Write-Host "`n== $m" -ForegroundColor Cyan }

# ---- 0.3 Audit GPO -----------------------------------------------------------------------------------------------
Say '0.3 Audit GPO on Domain Controllers'
$name = 'Audit - Directory and Account Changes'
$gpo  = Get-GPO -Name $name -ErrorAction SilentlyContinue
if (-not $gpo) {
    $gpo = New-GPO -Name $name -Comment 'AD agent lab 0.3: DS changes, group + user account management, success and failure'
}
$dcOU = $dom.DomainControllersContainer
if ((Get-GPInheritance -Target $dcOU).GpoLinks.DisplayName -notcontains $name) {
    New-GPLink -Guid $gpo.Id -Target $dcOU | Out-Null
}
# Advanced Audit Policy lives in the GPO's audit.csv; the GPMC editor writes the same file
$gid  = '{' + $gpo.Id.ToString().ToUpper() + '}'
$root = "\\$fqdn\SYSVOL\$fqdn\Policies\$gid"
$dir  = "$root\Machine\Microsoft\Windows NT\Audit"
if (-not (Test-Path "$dir\audit.csv")) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $g = '69ae-11d9-bed3-505054503030'
    @(
        'Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting,Setting Value'
        ",System,Audit Directory Service Changes,{0cce923c-$g},Success and Failure,,3"
        ",System,Audit Security Group Management,{0cce9237-$g},Success and Failure,,3"
        ",System,Audit User Account Management,{0cce9235-$g},Success and Failure,,3"
    ) | Set-Content -Path "$dir\audit.csv" -Encoding Ascii
    # tell computers the GPO now carries audit settings, and bump its version so they re-read it
    $obj = "CN=$gid,CN=Policies,CN=System,$dn"
    $ver = [int](Get-ADObject $obj -Properties versionNumber).versionNumber + 1
    $cse = '[{F3CCC681-B74C-4060-9F26-CD84525DCA2A}{0F3F3735-573D-9804-99E4-AB2A69BA5FD4}]'
    Set-ADObject $obj -Replace @{ gPCMachineExtensionNames = $cse; versionNumber = $ver }
    Set-Content -Path "$root\GPT.INI" -Value "[General]`r`nVersion=$ver" -Encoding Ascii
}
gpupdate /target:computer /force | Out-Null
$ap = auditpol /get /subcategory:"Directory Service Changes,Security Group Management,User Account Management"
$ap | Select-String 'Changes|Management' | ForEach-Object { '  ' + $_.Line.Trim() }
$auditOk = @($ap | Select-String 'Success and Failure').Count -eq 3

# ---- 0.4 _AGENTS, AI-Operators, ai-operator ------------------------------------------------------------------------
Say '0.4 OU _AGENTS, group AI-Operators, user ai-operator'
$agents = "OU=_AGENTS,$dn"
if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$agents'")) {
    New-ADOrganizationalUnit -Name '_AGENTS' -Path $dn `
        -Description 'AI agent identities. Outside _USERS so rights delegated there never cover the agent itself'
}
$groupsOU = @(Get-ADOrganizationalUnit -Filter "Name -eq 'Groups'")
if ($groupsOU.Count -ne 1) { throw "Expected exactly one OU named Groups, found $($groupsOU.Count)" }
$groupsDN = $groupsOU[0].DistinguishedName
if (-not (Get-ADGroup -Filter "Name -eq 'AI-Operators'")) {
    New-ADGroup -Name 'AI-Operators' -GroupScope Global -GroupCategory Security -Path $groupsDN `
        -Description 'AD agent lab: rights are delegated to this group, never to admin groups'
}
if (-not (Get-ADUser -Filter "SamAccountName -eq 'ai-operator'")) {
    $pw = Read-Host 'Choose a password for KENLAB\ai-operator (hidden, not stored)' -AsSecureString
    $u = @{
        Name = 'ai-operator'; SamAccountName = 'ai-operator'; UserPrincipalName = "ai-operator@$fqdn"
        Path = $agents; AccountPassword = $pw; Enabled = $true
        Description = 'AD agent lab helpdesk identity: Claude Code + admcp on CLIENT01'
    }
    New-ADUser @u
}

# ---- Proof: a membership change must log 4728 (member added) and 5136 (object modified) ---------------------------
Say 'Proof: 4728 + 5136 from a real group change'
function Toggle-Membership {
    if (Get-ADGroupMember 'AI-Operators' | Where-Object SamAccountName -eq 'ai-operator') {
        Remove-ADGroupMember 'AI-Operators' -Members 'ai-operator' -Confirm:$false
    }
    Add-ADGroupMember 'AI-Operators' -Members 'ai-operator'
    Start-Sleep -Seconds 5
}
function Find-Events($id, $since) {
    @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = $id; StartTime = $since } -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match 'AI-Operators' })
}
$mark = Get-Date; Toggle-Membership
$e4728 = Find-Events 4728 $mark; $e5136 = Find-Events 5136 $mark
if ($e5136.Count -eq 0) {
    Say 'No 5136 yet: adding audit SACLs (Everyone, write property, success + failure) on Groups and _USERS'
    foreach ($ou in $groupsDN, "OU=_USERS,$dn") {
        $acl  = Get-Acl "AD:$ou" -Audit
        $sid  = [Security.Principal.SecurityIdentifier]'S-1-1-0'
        # typed args: with plain strings two 4-arg constructors match and New-Object throws "ambiguous overloads"
        $rule = New-Object DirectoryServices.ActiveDirectoryAuditRule $sid,
            ([DirectoryServices.ActiveDirectoryRights]'WriteProperty'), ([Security.AccessControl.AuditFlags]'Success, Failure'),
            ([DirectoryServices.ActiveDirectorySecurityInheritance]'All')
        $acl.AddAuditRule($rule)
        Set-Acl "AD:$ou" $acl
    }
    # inherited audit rules reach child objects through AD's background SD propagation; toggling before the group
    # has the rule logs no 5136 (seen on DC01 22 Oct), so wait for it (up to 2 min)
    $grp = "AD:" + (Get-ADGroup 'AI-Operators').DistinguishedName
    foreach ($i in 1..24) {
        if ((Get-Acl $grp -Audit).Audit | Where-Object { $_.IsInherited -and $_.IdentityReference -match 'Everyone|S-1-1-0' }) { break }
        Start-Sleep -Seconds 5
    }
    "  AI-Operators has the inherited audit rule after about $(($i - 1) * 5) s"
    $mark = Get-Date; Toggle-Membership
    $e4728 = Find-Events 4728 $mark; $e5136 = Find-Events 5136 $mark
}

# ---- Summary ---------------------------------------------------------------------------------------------------------
Say 'Summary'
$member = (Get-ADPrincipalGroupMembership 'ai-operator' | Select-Object -ExpandProperty Name) -join ', '
[pscustomobject]@{
    'Audit GPO linked to Domain Controllers' = (Get-GPInheritance -Target $dcOU).GpoLinks.DisplayName -contains $name
    'auditpol: all 3 Success and Failure'     = $auditOk
    'ai-operator is in'                       = $member
    'ai-operator OU'                          = (Get-ADUser 'ai-operator').DistinguishedName
    '4728 events (member added)'              = $e4728.Count
    '5136 events (object modified)'           = $e5136.Count
} | Format-List
if ($e4728) { '4728: ' + ($e4728[0].Message -split "`n")[0].Trim() }
if ($e5136) { '5136: ' + ($e5136[0].Message -split "`n")[0].Trim() }
if ($auditOk -and $e4728.Count -gt 0 -and $e5136.Count -gt 0) { "`nPHASE 0.3 + 0.4: PASS" }
else { "`nPHASE 0.3 + 0.4: NOT YET, see the lines above" }
