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
# DC01 first (CLIENT01 needs the domain), each until its integration heartbeat reports the guest up
foreach ($vm in 'DC01', 'CLIENT01') {
    if ((Get-VM $vm).State -ne 'Running') { "starting $vm ..."; Start-VM -Name $vm }
    foreach ($i in 1..60) { if ((Get-VM $vm).Heartbeat -like 'Ok*') { break }; Start-Sleep 5 }
    $v = Get-VM $vm
    if ($v.Heartbeat -notlike 'Ok*') { throw "$vm did not come up within 5 minutes (heartbeat: $($v.Heartbeat))" }
    "$vm running, heartbeat: $($v.Heartbeat)"
}
Start-Sleep 30   # AD Web Services on DC01 start a little after the heartbeat
$cred = Get-Credential -UserName 'KENLAB\a-kkariuki' -Message 'Domain admin for DC01 and CLIENT01 (PowerShell Direct). Not stored.'

if ($Step -eq 'Deploy') {
    $zip = Get-ChildItem "$repo\dist\admcp-*.zip" | Sort-Object LastWriteTime | Select-Object -Last 1
    if (-not $zip) { throw "No dist\admcp-*.zip in $repo" }
    Copy-VMFile -Name CLIENT01 -SourcePath $zip.FullName -DestinationPath "C:\Lab\$($zip.Name)" -CreateFullPath -FileSource Host -Force
    foreach ($f in 'setup-lab.ps1', 'phase4-dc01.ps1', 'detector.ps1', 'setup-detector.ps1') {
        Copy-VMFile -Name DC01 -SourcePath "$repo\lab\$f" -DestinationPath "C:\Lab\$f" -CreateFullPath -FileSource Host -Force
    }
    "copied $($zip.Name) -> CLIENT01; setup-lab, phase4-dc01, detector, setup-detector -> DC01"

    "`n== DC01: 4.1 delegation, layout, out-of-scope test objects"
    $dc = Invoke-Command -VMName DC01 -Credential $cred -ScriptBlock {
        Get-Service ADWS, NTDS, DNS, Netlogon | ForEach-Object { "service $($_.Name): $($_.Status)" }
        & powershell -NoProfile -ExecutionPolicy Bypass -File C:\Lab\setup-lab.ps1 -Part Delegation
        & powershell -NoProfile -ExecutionPolicy Bypass -File C:\Lab\setup-detector.ps1 | ForEach-Object { "detector setup: $_" }
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
        # 24 Oct: CLIENT01 booted before DC01, so the AD module found no DC ("Unable to find a default server with Active
        # Directory Web Services running"). Find one now; if that fails, flush DNS, restart Netlogon and try again.
        # The real cause on 24 Oct: DC01 is the lab's DHCP server, CLIENT01 booted first, so it had no lease and therefore
        # no IPv4 DNS server (SRV lookups timed out). Renew the lease when no DNS server is set.
        if (-not (Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object ServerAddresses)) {
            "no IPv4 DNS server on CLIENT01 (no DHCP lease from DC01): ipconfig /renew"
            ipconfig /renew | Out-Null; Start-Sleep 5
        }
        "IPv4: " + ((Get-NetIPAddress -AddressFamily IPv4 | Where-Object InterfaceAlias -notmatch 'Loopback' |
            ForEach-Object { "$($_.InterfaceAlias)=$($_.IPAddress)" }) -join '; ') + "   DNS: " +
            ((Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object ServerAddresses | ForEach-Object { $_.ServerAddresses -join ',' }) -join '; ')
        $loc = cmd /c "nltest /dsgetdc:ad.kenmwara.com /ws /force 2>&1" | Out-String
        if ($loc -notmatch 'DC: \\\\') {
            "DC locator failed, retrying after flushdns + Netlogon restart:`n$loc"
            ipconfig /flushdns | Out-Null; Restart-Service Netlogon; Start-Sleep 10
            $loc = cmd /c "nltest /dsgetdc:ad.kenmwara.com /ws /force 2>&1" | Out-String
        }
        "DC locator: " + (($loc -split "`r?`n" | Where-Object { $_ -match 'DC:|Address:|Flags:' }) -join ' | ')
        "ADWS port 9389 on DC01 reachable: " + (Test-NetConnection DC01 -Port 9389 -WarningAction SilentlyContinue).TcpTestSucceeded
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
        # 5.8: Claude Code managed settings (admin-only file, so neither ai-operator nor the agent can loosen them).
        # Phase 0 keys stay; added: shells and file writes denied, the destructive tool always asks, no bypass mode,
        # and defaultMode pinned to "default" so auto mode can't skip the ask rule.
        $managed = 'C:\Program Files\ClaudeCode'
        New-Item -ItemType Directory -Force -Path $managed | Out-Null
        $json = @'
{
  "disableClaudeAiConnectors": true,
  "syncClaudeAiPlugins": false,
  "syncClaudeAiSkills": false,
  "enabledMcpjsonServers": ["admcp"],
  "permissions": {
    "defaultMode": "default",
    "disableBypassPermissionsMode": "disable",
    "ask": ["mcp__admcp__ad_disable_account"],
    "deny": ["Read(~/.claude/**)", "Bash", "PowerShell", "Write", "Edit", "NotebookEdit", "WebFetch", "WebSearch"],
    "blockReadsOutsideWorkingDirectories": true
  }
}
'@
        [IO.File]::WriteAllText("$managed\managed-settings.json", $json)   # UTF-8 without BOM; a BOM breaks JSON parsing
        "managed-settings.json written (deny shells + writes, ask before ad_disable_account, no bypass)"
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
"`n== DC01 Security log, last 2 hours (then the test objects are put back)"
Invoke-Command -VMName DC01 -Credential $cred -ScriptBlock {
    $since = (Get-Date).AddHours(-2)
    # put the change-tool targets back: lab-inside enabled and out of the test group; the real users the matrix touched
    Enable-ADAccount 'lab-inside'
    foreach ($g in 'Finance', 'IT', 'HR') {
        if (Get-ADGroupMember $g | Where-Object SamAccountName -eq 'lab-inside') { Remove-ADGroupMember $g -Members 'lab-inside' -Confirm:$false; "removed lab-inside from $g" }
    }
    "lab-inside enabled: " + (Get-ADUser 'lab-inside').Enabled
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
