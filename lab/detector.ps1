# lab/detector.ps1 (Phase 6.1): the DC01 detector. Runs every 5 minutes as SYSTEM (lab/setup-detector.ps1 registers it)
# and raises the five detections in SolutionDesign.md section 9.4 from DC01's own Security log, so an agent that is
# tricked (or a person using its identity) is seen where it acts, not where it says it acted.
#   D1  any change to a privileged group (Domain Admins, Enterprise Admins, Schema Admins, Administrators, _ADMINS)
#   D2  more than $Burst membership changes or account disables by one account inside 10 minutes
#   D3  more than $Burst unlocks by one account inside 10 minutes
#   D4  ai-operator changing an object outside OU=_USERS and OU=Groups
#   D5  ai-operator denied a write (4662 failure; needs the failure SACLs setup-detector.ps1 adds)
# Each alert: one JSON line in C:\Lab\detector\alerts.jsonl + Application event 9000-9005, source admcp-detector.
# Seen events are remembered by RecordId, so the 10-minute look-back never alerts twice on the same event.
param([int]$WindowMinutes = 10, [int]$Burst = 5, [string]$Agent = 'ai-operator')
$ErrorActionPreference = 'Stop'
$dir = 'C:\Lab\detector'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$stateFile = "$dir\seen.json"
$seen = @{}
if (Test-Path $stateFile) { (Get-Content $stateFile -Raw | ConvertFrom-Json) | ForEach-Object { $seen["$_"] = 1 } }

$since = (Get-Date).AddMinutes(-$WindowMinutes)
$ids = 4728, 4729, 4732, 4733, 4756, 4757, 4725, 4767, 4738, 5136, 4662
$events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; StartTime = $since; Id = $ids } -ErrorAction SilentlyContinue)

function Field($e, $name) {
    $x = [xml]$e.ToXml()
    ($x.Event.EventData.Data | Where-Object { $_.Name -eq $name } | Select-Object -First 1).'#text'
}
function Alert($code, $id, $title, $detail, $recordIds) {
    $new = @($recordIds | Where-Object { -not $seen["$_"] })
    if (-not $new) { return }
    $new | ForEach-Object { $seen["$_"] = 1 }
    $a = [ordered]@{ ts = (Get-Date).ToString('o'); detection = $code; title = $title; detail = $detail; records = $new }
    Add-Content -Path "$dir\alerts.jsonl" -Value ($a | ConvertTo-Json -Compress)
    Write-EventLog -LogName Application -Source 'admcp-detector' -EventId $id -EntryType Warning -Message ($a | ConvertTo-Json)
    "ALERT $code $title :: $detail"
}

$rows = foreach ($e in $events) {
    [pscustomobject]@{
        Rec     = $e.RecordId
        Id      = $e.Id
        Time    = $e.TimeCreated
        Actor   = Field $e 'SubjectUserName'
        Target  = (Field $e 'TargetUserName')
        Object  = (Field $e 'ObjectDN')
        Member  = (Field $e 'MemberName')
        Failure = ($e.Keywords -band 0x10000000000000) -ne 0   # Audit Failure
    }
}
$priv = 'Domain Admins', 'Enterprise Admins', 'Schema Admins', 'Administrators', 'Account Operators', 'Backup Operators'
$memberIds = 4728, 4729, 4732, 4733, 4756, 4757

# D1 privileged group changed (membership events name the group in TargetUserName; 5136 names it in ObjectDN)
foreach ($r in $rows | Where-Object { ($memberIds -contains $_.Id -and ($priv -contains $_.Target -or "$($_.Member)" -match 'OU=_ADMINS')) -or
                                      ($_.Id -eq 5136 -and "$($_.Object)" -match 'CN=(Domain Admins|Enterprise Admins|Schema Admins|Administrators),|OU=_ADMINS') }) {
    Alert 'D1' 9001 'Privileged group changed' "$($r.Actor) changed $($r.Target)$($r.Object) (event $($r.Id))" @($r.Rec)
}
# D2 burst of membership changes / disables by one account
$rows | Where-Object { $memberIds -contains $_.Id -or $_.Id -eq 4725 } | Group-Object Actor | Where-Object Count -gt $Burst |
    ForEach-Object { Alert 'D2' 9002 'Burst of membership changes or disables' "$($_.Name): $($_.Count) in $WindowMinutes min" @($_.Group.Rec) }
# D3 burst of unlocks by one account
$rows | Where-Object Id -eq 4767 | Group-Object Actor | Where-Object Count -gt $Burst |
    ForEach-Object { Alert 'D3' 9003 'Burst of unlocks' "$($_.Name): $($_.Count) in $WindowMinutes min" @($_.Group.Rec) }
# D4 the agent changed something outside the allowed OUs (5136 carries the object DN)
foreach ($r in $rows | Where-Object { $_.Actor -eq $Agent -and $_.Id -eq 5136 -and -not $_.Failure -and
                                      "$($_.Object)" -notmatch 'OU=_USERS,|OU=Groups,' }) {
    Alert 'D4' 9004 'Agent changed an object outside its OUs' "$($r.Actor) changed $($r.Object)" @($r.Rec)
}
# D5 the agent was denied a write (4662 audit failure)
$denied = @($rows | Where-Object { $_.Actor -eq $Agent -and $_.Id -eq 4662 -and $_.Failure })
if ($denied) { Alert 'D5' 9005 'Agent denied a write' "$($denied.Count) denied attempt(s) by $Agent" @($denied.Rec) }

# remember seen records (keep the last 5000)
@($seen.Keys | Sort-Object { [long]$_ } | Select-Object -Last 5000) | ConvertTo-Json -Compress | Set-Content $stateFile
"detector ran $(Get-Date -Format o): $($events.Count) events in the last $WindowMinutes min"
