<#
Phase 3 + 4 on the VMs, driven from the LAPTOP in an elevated PowerShell (PowerShell Direct, no lab network needed):
    powershell -ExecutionPolicy Bypass -File lab\phase34-host.ps1 -Step Deploy     # DC01 delegation + test objects; CLIENT01 code, checks, event source
    (then, signed in to CLIENT01 as KENLAB\ai-operator:  powershell -ExecutionPolicy Bypass -File C:\ADAgent\lab\run-checks-as-operator.ps1)
    powershell -ExecutionPolicy Bypass -File lab\phase34-host.ps1 -Step Evidence   # the report + admcp event log + DC01 Security log
Asks once for KENLAB\a-kkariuki in the Windows credential box: typed by Ken, never stored or printed.
#>
#Requires -RunAsAdministrator
param([ValidateSet('Deploy', 'Evidence')][string]$Step = 'Deploy')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
foreach ($vm in 'DC01', 'CLIENT01') {
    $v = Get-VM $vm
    if ($v.State -ne 'Running') { throw "$vm is $($v.State): start it and wait for it to boot" }
    "$vm running, heartbeat: $($v.Heartbeat)"
}
$cred = Get-Credential -UserName 'KENLAB\a-kkariuki' -Message 'Domain admin for DC01 and CLIENT01 (PowerShell Direct). Not stored.'

if ($Step -eq 'Deploy') {
    $zip = Get-ChildItem "$repo\dist\admcp-*.zip" | Sort-Object LastWriteTime | Select-Object -Last 1
    if (-not $zip) { throw "No dist\admcp-*.zip in $repo" }
    Copy-VMFile -Name CLIENT01 -SourcePath $zip.FullName -DestinationPath "C:\Lab\$($zip.Name)" -CreateFullPath -FileSource Host -Force
    foreach ($f in 'setup-lab.ps1', 'phase4-dc01.ps1') {
        Copy-VMFile -Name DC01 -SourcePath "$repo\lab\$f" -DestinationPath "C:\Lab\$f" -CreateFullPath -FileSource Host -Force
    }
    "copied $($zip.Name) -> CLIENT01, setup-lab.ps1 + phase4-dc01.ps1 -> DC01"

    "`n== DC01: 4.1 delegation, layout, out-of-scope test objects"
    $dc = Invoke-Command -VMName DC01 -Credential $cred -ScriptBlock {
        & powershell -NoProfile -ExecutionPolicy Bypass -File C:\Lab\setup-lab.ps1 -Part Delegation
        & powershell -NoProfile -ExecutionPolicy Bypass -File C:\Lab\phase4-dc01.ps1
    }
    $dc
    $text = ($dc | Out-String)
    $layout = $text.Substring($text.IndexOf('{')) | ConvertFrom-Json
    $targetsJson = $layout.targets | ConvertTo-Json -Compress

    "`n== CLIENT01: code $($zip.Name), checks, event source, targets"
    Invoke-Command -VMName CLIENT01 -Credential $cred -ArgumentList $zip.Name, $targetsJson -ScriptBlock {
        param($zipName, $targetsJson)
        $App = 'C:\ADAgent'
        Expand-Archive -Path "C:\Lab\$zipName" -DestinationPath $App -Force
        # admins change the code; everyone else (ai-operator included) can only read and run it
        icacls $App /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
        & "$App\.venv\Scripts\python.exe" -m pip install --quiet --disable-pip-version-check -r "$App\requirements.txt"
        Push-Location $App
        try {
            & "$App\.venv\Scripts\python.exe" tests\check_server.py
            & "$App\.venv\Scripts\python.exe" tests\check_runner.py
        } finally { Pop-Location }
        & powershell -NoProfile -ExecutionPolicy Bypass -File "$App\lab\setup-lab.ps1" -Part EventSource
        $out = 'C:\Users\Public\Documents\admcp'
        New-Item -ItemType Directory -Force -Path $out | Out-Null
        icacls $out /grant '*S-1-5-32-545:(OI)(CI)M' | Out-Null   # ai-operator writes its report here
        [IO.File]::WriteAllText("$out\targets.json", $targetsJson)
        "targets.json: $targetsJson"
    }
    "`nNext: sign in to CLIENT01 as KENLAB\ai-operator and run:"
    "  powershell -ExecutionPolicy Bypass -File C:\ADAgent\lab\run-checks-as-operator.ps1"
    return
}

"== CLIENT01: the ai-operator report"
Invoke-Command -VMName CLIENT01 -Credential $cred -ScriptBlock {
    Get-Content 'C:\Users\Public\Documents\admcp\phase34-report.txt' -Raw
    "== CLIENT01 Application log, source admcp (latest 12)"
    Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'admcp' } -MaxEvents 12 -ErrorAction SilentlyContinue |
        ForEach-Object { '{0:HH:mm:ss}  {1}' -f $_.TimeCreated, $_.Message.Substring(0, [math]::Min(170, $_.Message.Length)) }
}
"`n== DC01 Security log, last 2 hours"
Invoke-Command -VMName DC01 -Credential $cred -ScriptBlock {
    $since = (Get-Date).AddHours(-2)
    $ids = 4624, 4625, 4768, 4769, 4738, 4740, 4767, 4725, 4722, 4728, 4729, 4756, 4757, 5136, 4662
    Get-WinEvent -FilterHashtable @{ LogName = 'Security'; StartTime = $since; Id = $ids } -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match 'ai-operator' } | Group-Object Id |
        ForEach-Object { '{0}  x{1}  {2}' -f $_.Name, $_.Count, (($_.Group[0].Message -split "`r?`n")[0]) }
    "-- account and group changes (4722/4725/4738/4767/4728/4729/5136), newest first"
    Get-WinEvent -FilterHashtable @{ LogName = 'Security'; StartTime = $since; Id = 4722, 4725, 4738, 4767, 4728, 4729, 5136 } -MaxEvents 30 -ErrorAction SilentlyContinue |
        ForEach-Object {
            $m = $_.Message
            $subj = if ($m -match 'Subject:[\s\S]*?Account Name:\s+(\S+)') { $Matches[1] } else { '?' }
            $tgt  = if ($m -match '(?:Target Account|Member|Object):[\s\S]*?(?:Account Name|DN):\s+(.+)') { $Matches[1].Trim() } else { '' }
            '{0:HH:mm:ss}  {1}  by {2}  target {3}' -f $_.TimeCreated, $_.Id, $subj, $tgt.Substring(0, [math]::Min(80, $tgt.Length))
        }
}
