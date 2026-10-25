# lab/prove-detections.ps1 (Phase 6.2): stage one event per detection in SolutionDesign 9.4, run the detector, report
# which alerts fired. Elevated, on DC01, as a lab admin; -Agent is ai-operator's credential (D4 and D5 must be done
# AS the agent). Every staged change is undone before the script ends, and the end state is checked.
param([Parameter(Mandatory)][pscredential]$Agent, [string]$InUser = 'lab-inside', [string]$OutUser = 'lab-outside')
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
$start = Get-Date
$dom = Get-ADDomain
$dn = $dom.DistinguishedName
$fin = Get-ADGroup -SearchBase "OU=Groups,$dn" -Filter "Name -like '*Finance*'" | Select-Object -First 1
$wasFinance = @(Get-ADGroupMember $fin | Where-Object SamAccountName -eq $InUser).Count -gt 0
"start $($start.ToString('o')); Finance group '$($fin.Name)', $InUser member at start: $wasFinance"

# D1: a privileged group changes (Backup Operators is in the detector's list); undone at once
Add-ADGroupMember 'Backup Operators' -Members $OutUser
Remove-ADGroupMember 'Backup Operators' -Members $OutUser -Confirm:$false
"D1 staged: $OutUser added to and removed from Backup Operators"

# D2: more than 5 membership changes by one account inside 10 minutes (8 here), ending in the starting state
1..4 | ForEach-Object {
    if ($wasFinance) { Remove-ADGroupMember $fin -Members $InUser -Confirm:$false; Add-ADGroupMember $fin -Members $InUser }
    else { Add-ADGroupMember $fin -Members $InUser; Remove-ADGroupMember $fin -Members $InUser -Confirm:$false }
}
"D2 staged: 8 membership changes on $($fin.Name)"

# D3: more than 5 unlocks by one account inside 10 minutes: lock $InUser with wrong passwords, unlock, 6 times
$thr = (Get-ADDefaultDomainPasswordPolicy).LockoutThreshold
if ($thr -lt 1) { "D3 NOT staged: no lockout threshold in the domain policy" } else {
    $unlocks = 0
    foreach ($i in 1..6) {
        for ($k = 0; $k -lt $thr + 3 -and -not (Get-ADUser $InUser -Properties LockedOut).LockedOut; $k++) {
            # a failed bind = one bad password. No Dispose(): PowerShell's adapter re-binds to read the member and rethrows
            $de = New-Object DirectoryServices.DirectoryEntry("LDAP://$env:COMPUTERNAME/$dn", "$($dom.NetBIOSName)\$InUser", "wrong-$([guid]::NewGuid())")
            try { $null = $de.NativeObject } catch {}
        }
        if ((Get-ADUser $InUser -Properties LockedOut).LockedOut) { Unlock-ADAccount $InUser; $unlocks++ }
    }
    "D3 staged: $unlocks lock + unlock cycles (threshold $thr)"
}

# D4: the agent changes an object outside its OUs: its own phone number (SELF may write personal info by default)
try {
    Set-ADUser 'ai-operator' -OfficePhone '555-0100' -Credential $Agent
    Set-ADUser 'ai-operator' -Clear telephoneNumber -Credential $Agent
    "D4 staged: ai-operator wrote and cleared its own telephoneNumber (in OU=_AGENTS)"
} catch { "D4 NOT staged: $($_.Exception.Message)" }

# D5: the agent is refused a write (lab-outside sits in _LABTEST, outside its delegation)
try {
    Disable-ADAccount $OutUser -Credential $Agent
    Enable-ADAccount $OutUser
    "D5 PROBLEM: ai-operator DISABLED $OutUser (delegation breach); re-enabled it"
} catch { "D5 staged: refused as expected ($($_.Exception.Message))" }

"waiting 30 s for 5136 (written ~9 s after a change), then running the detector"
Start-Sleep 30
& C:\Lab\detector.ps1 -WindowMinutes 20 | ForEach-Object { "  detector: $_" }

"== alerts since $($start.ToString('T'))"
$alerts = @()
if (Test-Path C:\Lab\detector\alerts.jsonl) {
    $alerts = Get-Content C:\Lab\detector\alerts.jsonl | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { [datetime]$_.ts -ge $start }
}
foreach ($d in 'D1', 'D2', 'D3', 'D4', 'D5') {
    $a = @($alerts | Where-Object detection -eq $d)
    "{0}: {1}" -f $d, $(if ($a) { "FIRED x$($a.Count): $($a[0].detail)" } else { 'no alert' })
}
"4662 failures by ai-operator since start: " + @(Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4662; StartTime=$start} -ErrorAction SilentlyContinue |
    Where-Object { ($_.Keywords -band 0x10000000000000) -and $_.Properties[1].Value -eq 'ai-operator' }).Count

"== end state"
"Backup Operators has $OutUser : " + [bool](Get-ADGroupMember 'Backup Operators' | Where-Object SamAccountName -eq $OutUser)
"$InUser in $($fin.Name): " + [bool](Get-ADGroupMember $fin | Where-Object SamAccountName -eq $InUser) + " (start: $wasFinance)"
"$InUser locked: " + (Get-ADUser $InUser -Properties LockedOut).LockedOut
"$OutUser enabled: " + (Get-ADUser $OutUser).Enabled
"ai-operator telephoneNumber: '" + (Get-ADUser 'ai-operator' -Properties telephoneNumber).telephoneNumber + "'"
