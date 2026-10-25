# lab/phase4-dc01.ps1 (Phase 4.2 prep): read the real lab layout and create the out-of-scope test objects. DC01, elevated.
# The "one step outside" tests in test-delegation.ps1 must never touch a real or privileged object, so this makes an OU
# _LABTEST (outside _USERS and Groups, nothing delegated there) holding one non-admin user and one group. Idempotent.
# The test user's password is random, used once at creation, and never stored or printed. Last output = JSON.
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
$dn = (Get-ADDomain).DistinguishedName
$users = "OU=_USERS,$dn"
$groupsDN = @(Get-ADOrganizationalUnit -Filter "Name -eq 'Groups'")[0].DistinguishedName
$test = "OU=_LABTEST,$dn"

if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$test'")) {
    New-ADOrganizationalUnit -Name '_LABTEST' -Path $dn -ProtectedFromAccidentalDeletion $false `
        -Description 'AD agent lab: out-of-scope targets for the delegation matrix. Nothing is delegated here.'
}
if (-not (Get-ADUser -Filter "SamAccountName -eq 'lab-outside'")) {
    $bytes = New-Object byte[] 24; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $sec = ConvertTo-SecureString ([Convert]::ToBase64String($bytes) + 'aA1!') -AsPlainText -Force
    New-ADUser -Name 'lab-outside' -SamAccountName 'lab-outside' -Path $test -Enabled $true -AccountPassword $sec `
        -Description 'Delegation test target outside _USERS (non-admin, no group memberships)'
    Remove-Variable sec, bytes
}
if (-not (Get-ADGroup -Filter "Name -eq 'lab-outside-group'")) {
    New-ADGroup -Name 'lab-outside-group' -GroupScope Global -GroupCategory Security -Path $test `
        -Description 'Delegation test target outside OU=Groups'
}

$inUsers = @(Get-ADUser -SearchBase $users -Filter 'Enabled -eq $true' -ResultSetSize 200 |
    Sort-Object SamAccountName | Select-Object -First 2)
$inGroup = @(Get-ADGroup -SearchBase $groupsDN -Filter "Name -ne 'AI-Operators'" | Sort-Object Name | Select-Object -First 1)
$aces = @((Get-Acl "AD:$users").Access) + @((Get-Acl "AD:$groupsDN").Access) |
    Where-Object { "$($_.IdentityReference)" -like '*AI-Operators*' } |
    ForEach-Object { "$($_.ActiveDirectoryRights) object:$($_.ObjectType) on:$($_.InheritedObjectType)" }

[ordered]@{
    domainDN       = $dn
    usersOU        = $users
    groupsOU       = $groupsDN
    departmentOUs  = @(Get-ADOrganizationalUnit -SearchBase $users -SearchScope OneLevel -Filter * | ForEach-Object Name)
    usersInUSERS   = @(Get-ADUser -SearchBase $users -Filter * -ResultSetSize 5000).Count
    groupsInGroups = @(Get-ADGroup -SearchBase $groupsDN -Filter * | ForEach-Object Name)
    aiOperatorAces = $aces
    targets        = [ordered]@{
        InUser = $inUsers[0].SamAccountName; Member = $inUsers[1].SamAccountName; InGroup = $inGroup[0].Name
        OutUser = 'lab-outside'; OutGroup = 'lab-outside-group'
    }
} | ConvertTo-Json -Depth 4
