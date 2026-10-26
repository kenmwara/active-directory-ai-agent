# lab/capture-evidence.ps1 (Phase 7.2): after the agent has been given a batch of test prompts on CLIENT01, pull the
# evidence from both VMs so each finding can be written. Read-only. Elevated, on the host.
#   DC01    : Security events (the account-change + access IDs) and the detector's alerts, since the cutoff
#   CLIENT01: ai-operator's call log (one JSON line per tool the agent actually invoked), since the cutoff
# The agent's own chat replies are only in the CLIENT01 window; the operator reports those. This pairs the DC-side
# ground truth (D13) with the agent's tool calls so a finding is not taken from the agent's word.
param([int]$SinceMinutes = 90, [string]$OutFile = "$PSScriptRoot\..\evidence\capture-$((Get-Date).ToString('yyyyMMdd-HHmmss')).txt")
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null
Start-Transcript -Path $OutFile -Force | Out-Null
try {
    $cutoff = (Get-Date).AddMinutes(-$SinceMinutes)
    "cutoff: $($cutoff.ToString('o'))  (last $SinceMinutes min)"
    $cred = Get-Credential -UserName 'KENLAB\a-kkariuki' -Message "Lab admin password (read-only evidence pull)"

    "== DC01 Security events"
    Invoke-Command -VMName DC01 -Credential $cred -ArgumentList $cutoff -ScriptBlock {
        param($cutoff)
        function F($e, $n) { (([xml]$e.ToXml()).Event.EventData.Data | Where-Object Name -eq $n | Select-Object -First 1).'#text' }
        $ids = 4728, 4729, 4732, 4733, 4756, 4757, 4725, 4722, 4740, 4767, 5136, 4662
        $ev = @(Get-WinEvent -FilterHashtable @{LogName = 'Security'; Id = $ids; StartTime = $cutoff } -ErrorAction SilentlyContinue)
        "events: $($ev.Count) since cutoff"
        $ev | Sort-Object TimeCreated | ForEach-Object {
            $fail = ($_.Keywords -band 0x10000000000000) -ne 0
            "{0} {1} {2} actor={3} target={4} member={5} obj={6}{7}" -f `
                $_.TimeCreated.ToString('HH:mm:ss'), $_.Id, $(if ($fail) { 'FAIL' } else { 'ok  ' }), (F $_ 'SubjectUserName'), (F $_ 'TargetUserName'), (F $_ 'MemberName'), (F $_ 'ObjectDN'), ''
        }
    } | ForEach-Object { "  $_" }

    "== DC01 detector alerts"
    Invoke-Command -VMName DC01 -Credential $cred -ArgumentList $cutoff -ScriptBlock {
        param($cutoff)
        if (Test-Path C:\Lab\detector\alerts.jsonl) {
            Get-Content C:\Lab\detector\alerts.jsonl | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { [datetime]$_.ts -ge $cutoff } |
                ForEach-Object { "{0} {1} {2} :: {3}" -f ([datetime]$_.ts).ToString('HH:mm:ss'), $_.detection, $_.title, $_.detail }
        } else { "no alerts file" }
    } | ForEach-Object { "  $_" }

    "== run the detector once more so late events are caught"
    Invoke-Command -VMName DC01 -Credential $cred -ScriptBlock { & C:\Lab\detector.ps1 -WindowMinutes 90 | Select-Object -Last 1 } | ForEach-Object { "  $_" }

    "== CLIENT01 agent call log (ai-operator)"
    Invoke-Command -VMName CLIENT01 -Credential $cred -ArgumentList $cutoff -ScriptBlock {
        param($cutoff)
        $p = 'C:\Users\ai-operator\AppData\Local\admcp\calls.jsonl'
        if (-not (Test-Path $p)) { "no call log at $p"; return }
        Get-Content $p | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { [datetime]$_.ts -ge $cutoff } |
            ForEach-Object { "{0} {1} caller={2} outcome={3} {4}" -f ([datetime]$_.ts).ToString('HH:mm:ss'), $_.tool, $_.caller, $_.outcome, (($_.args | ConvertTo-Json -Compress) 2>$null) }
    } | ForEach-Object { "  $_" }
} catch { "ERROR: " + $_.Exception.Message }
"transcript end"
Stop-Transcript | Out-Null
