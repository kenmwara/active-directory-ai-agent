<#
CLIENT01 can't resolve internet names (Claude Code: "Can't reach the API server ... ENOTFOUND"). LAPTOP, elevated.
CLIENT01's only DNS server is DC01, and DC01 forwards outside names. Dcpromo copied the INTERNET adapter's DNS server
at promotion time (the Hyper-V Default Switch gateway, 172.23.x.1 then), and the Default Switch picks a new subnet when
the laptop restarts (172.17.x on 24 Oct), so the forwarder goes stale. Fix: forward to public resolvers, which don't
move. Prints the before and after on both VMs.
#>
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Continue'
$cred = Get-Credential -UserName 'KENLAB\a-kkariuki' -Message 'Domain admin for DC01 and CLIENT01 (PowerShell Direct). Not stored.'
Invoke-Command -VMName DC01 -Credential $cred -ScriptBlock { } -ErrorAction Stop   # stop at a mistyped password
$name = 'api.anthropic.com'

"== DC01"
Invoke-Command -VMName DC01 -Credential $cred -ArgumentList $name -ScriptBlock {
    param($name)
    $resolves = { param($n, $server) try { [bool](Resolve-DnsName $n -Server $server -DnsOnly -ErrorAction Stop) } catch { $false } }
    $ip = Get-NetIPConfiguration -InterfaceAlias INTERNET
    "INTERNET: $($ip.IPv4Address.IPAddress) gateway $($ip.IPv4DefaultGateway.NextHop)"
    "RemoteAccess (NAT): " + (Get-Service RemoteAccess).Status
    "forwarders before: " + ((Get-DnsServerForwarder).IPAddress.IPAddressToString -join ', ')
    "1.1.1.1:443 reachable: " + (Test-NetConnection 1.1.1.1 -Port 443 -WarningAction SilentlyContinue).TcpTestSucceeded
    if (-not (& $resolves $name '127.0.0.1')) {
        Set-DnsServerForwarder -IPAddress 1.1.1.1, 8.8.8.8
        Clear-DnsServerCache -Force
        "forwarders set: " + ((Get-DnsServerForwarder).IPAddress.IPAddressToString -join ', ')
    }
    "DC01 resolves ${name}: " + (& $resolves $name '127.0.0.1')
}
"== CLIENT01"
Invoke-Command -VMName CLIENT01 -Credential $cred -ArgumentList $name -ScriptBlock {
    param($name)
    Clear-DnsClientCache
    "resolves ${name}: " + [bool](Resolve-DnsName $name -ErrorAction SilentlyContinue)
    "${name}:443 reachable: " + (Test-NetConnection $name -Port 443 -WarningAction SilentlyContinue).TcpTestSucceeded
}
