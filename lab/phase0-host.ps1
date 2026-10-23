<#
Phase 0.1 + 0.2 (and 0.7 with -Final) of PhasedSolutionPlan.md. Run on the LAPTOP in an elevated PowerShell:
    powershell -ExecutionPolicy Bypass -File lab\phase0-host.ps1          # checkpoints 'pre-agent', guest services, copies
    powershell -ExecutionPolicy Bypass -File lab\phase0-host.ps1 -Final   # checkpoints 'pre-build' once Phase 0 passes
Idempotent: existing checkpoints and files are left alone or overwritten, never deleted.
#>
#Requires -RunAsAdministrator
param([switch]$Final)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$vms  = 'DC01', 'CLIENT01'

$free = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
"C: free: $free GB"
if ($free -lt 8) { throw "Only $free GB free on C:. Free some space before taking checkpoints." }

# Disk (22 Oct: C: fell from 21 to 2.8 GB in 2 h): AutomaticStopAction Save keeps a file the size of the VM's RAM on
# disk while it runs, and Standard checkpoints save RAM too. ShutDown + Production drop both; Hyper-V only takes these
# while the VM is off.
foreach ($vm in $vms) {
    $v = Get-VM $vm
    if ($v.State -eq 'Off' -and ($v.AutomaticStopAction -ne 'ShutDown' -or $v.CheckpointType -ne 'Production')) {
        Set-VM -Name $vm -AutomaticStopAction ShutDown -CheckpointType Production
    }
    $v = Get-VM $vm
    "$vm stop action: $($v.AutomaticStopAction), checkpoint type: $($v.CheckpointType), state: $($v.State)"
}

$name = if ($Final) { 'pre-build' } else { 'pre-agent' }
foreach ($vm in $vms) {
    if (-not (Get-VMSnapshot -VMName $vm -Name $name -ErrorAction SilentlyContinue)) {
        Checkpoint-VM -Name $vm -SnapshotName $name
    }
    # the new checkpoint can take a few seconds to show up (22 Oct: files on disk, missing from the list); prove it
    foreach ($i in 1..15) { if (Get-VMSnapshot -VMName $vm -Name $name -ErrorAction SilentlyContinue) { break }; Start-Sleep 2 }
    if (-not (Get-VMSnapshot -VMName $vm -Name $name -ErrorAction SilentlyContinue)) { throw "$vm has no '$name' checkpoint" }
    "$vm checkpoints: " + ((Get-VMSnapshot -VMName $vm).Name -join ', ')
}
if ($Final) { return }

# 0.2: Guest Service Interface lets Copy-VMFile put files in the guest with no network and no credentials (D15)
foreach ($vm in $vms) { Enable-VMIntegrationService -VMName $vm -Name 'Guest Service Interface' }
Start-Sleep -Seconds 5

$zip = Get-ChildItem "$repo\dist\admcp-*.zip" | Sort-Object LastWriteTime | Select-Object -Last 1
if (-not $zip) { throw "No dist\admcp-*.zip in $repo" }
$copies = @(
    @('DC01',     "$repo\lab\phase0-dc01.ps1",     'C:\Lab\phase0-dc01.ps1'),
    @('CLIENT01', "$repo\lab\phase0-client01.ps1", 'C:\Lab\phase0-client01.ps1'),
    @('CLIENT01', $zip.FullName,                    "C:\Lab\$($zip.Name)")
)
foreach ($c in $copies) {
    Copy-VMFile -Name $c[0] -SourcePath $c[1] -DestinationPath $c[2] -CreateFullPath -FileSource Host -Force
    "copied $(Split-Path $c[1] -Leaf) -> $($c[0]) $($c[2])"
}
"Next: on DC01 run  powershell -ExecutionPolicy Bypass -File C:\Lab\phase0-dc01.ps1"
