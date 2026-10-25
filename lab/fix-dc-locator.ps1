<#
Diagnose + fix "Unable to find a default server with Active Directory Web Services running" on CLIENT01. LAPTOP, elevated.
24 Oct: after a cold start of DC01, nltest /dsgetdc /ws on CLIENT01 returned 1355 (no such domain) although TCP 9389 on
DC01 answered. Known cause: ADWS came up before NTDS/Netlogon were ready, so the DC never advertised the web-service
flag. Checks the locator with and without /ws on both VMs, restarts ADWS on DC01 only if /ws fails there, re-checks.
#>
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Continue'
$cred = Get-Credential -UserName 'KENLAB\a-kkariuki' -Message 'Domain admin for DC01 and CLIENT01 (PowerShell Direct). Not stored.'
$probe = {
    $out = [ordered]@{}
    $out['dsgetdc']    = ((nltest /dsgetdc:ad.kenmwara.com /force 2>&1) -join ' ') -replace '\s+', ' '
    $out['dsgetdc_ws'] = ((nltest /dsgetdc:ad.kenmwara.com /ws /force 2>&1) -join ' ') -replace '\s+', ' '
    $out['srv']        = try { (Resolve-DnsName -Type SRV '_ldap._tcp.dc._msdcs.ad.kenmwara.com' -ErrorAction Stop | Where-Object NameTarget | ForEach-Object NameTarget) -join ',' } catch { "SRV lookup failed: $($_.Exception.Message)" }
    $out['dns']        = (Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object ServerAddresses | ForEach-Object { "$($_.InterfaceAlias)=$($_.ServerAddresses -join ',')" }) -join '; '
    $out | ConvertTo-Json -Compress
}
"== DC01 before";    Invoke-Command -VMName DC01 -Credential $cred -ScriptBlock $probe
"== CLIENT01 before"; Invoke-Command -VMName CLIENT01 -Credential $cred -ScriptBlock $probe
"== DC01: restart ADWS if the DC itself can't find a DC with the web-service flag"
Invoke-Command -VMName DC01 -Credential $cred -ScriptBlock {
    $ws = (nltest /dsgetdc:ad.kenmwara.com /ws /force 2>&1) -join ' '
    if ($ws -notmatch 'DC: \\\\') { Restart-Service ADWS -Force; Start-Sleep 20; "ADWS restarted" } else { "ADWS flag already advertised" }
    "ADWS: " + (Get-Service ADWS).Status
}
"== CLIENT01: flush, re-register, re-check"
Invoke-Command -VMName CLIENT01 -Credential $cred -ScriptBlock { ipconfig /flushdns | Out-Null; Restart-Service Netlogon; Start-Sleep 10 }
Invoke-Command -VMName CLIENT01 -Credential $cred -ScriptBlock $probe
"== CLIENT01: AD module smoke test as admin"
Invoke-Command -VMName CLIENT01 -Credential $cred -ScriptBlock { try { (Get-ADDomain -ErrorAction Stop).DNSRoot + ' OK via ' + (Get-ADDomainController -Discover -Service ADWS -ErrorAction Stop).HostName } catch { "AD module: $($_.Exception.Message)" } }
