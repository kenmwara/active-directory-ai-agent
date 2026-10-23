<#
Phase 0.5 + 0.6 (admin part) of PhasedSolutionPlan.md. Run ON CLIENT01 in an elevated PowerShell as KENLAB\a-kkariuki:
    powershell -ExecutionPolicy Bypass -File C:\Lab\phase0-client01.ps1
Installs RSAT (AD + Group Policy), Python 3.12+ and Git (Claude Code on Windows uses Git Bash; no credentials go on
this VM, D15), unpacks the repo to C:\ADAgent read-only for everyone but admins, builds the venv and runs the stdio
check. winget asks you to accept its terms: answer those prompts yourself. Idempotent.
#>
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$App = 'C:\ADAgent'
function Say($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

Say '0.5 RSAT: Active Directory + Group Policy Management'
foreach ($cap in 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0', 'Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0') {
    if ((Get-WindowsCapability -Online -Name $cap).State -ne 'Installed') { Add-WindowsCapability -Online -Name $cap | Out-Null }
    '  {0}: {1}' -f $cap.Split('~')[0], (Get-WindowsCapability -Online -Name $cap).State
}

Say '0.5 Python 3.12+ and Git'
$pyOk = (Get-Command py.exe -ErrorAction SilentlyContinue) -and
        ((& py -3 -c 'import sys; print(sys.version_info >= (3, 12))') -eq 'True')
if (-not $pyOk) { winget install --id Python.Python.3.12 --exact --scope machine; Refresh-Path }
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { winget install --id Git.Git --exact --scope machine; Refresh-Path }
'  ' + (& py -3 --version)
'  ' + (& git --version)

Say '0.6 Repo copy, venv, stdio check'
$zip = Get-ChildItem 'C:\Lab\admcp-*.zip' | Sort-Object LastWriteTime | Select-Object -Last 1
if (-not $zip) { throw 'No C:\Lab\admcp-*.zip. Run lab\phase0-host.ps1 on the laptop first.' }
New-Item -ItemType Directory -Force -Path $App | Out-Null
Expand-Archive -Path $zip.FullName -DestinationPath $App -Force
# Admins change the code; everyone else, ai-operator included, can only read and run it (the agent can't edit its own tools)
icacls $App /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
if (-not (Test-Path "$App\.venv\Scripts\python.exe")) { & py -3 -m venv "$App\.venv" }
& "$App\.venv\Scripts\python.exe" -m pip install --quiet --disable-pip-version-check -r "$App\requirements.txt"
Push-Location $App
try { & "$App\.venv\Scripts\python.exe" tests\check_server.py } finally { Pop-Location }
"  repo: $($zip.Name) -> $App"

Say '0.6 Claude Code managed settings (admin-only, so neither ai-operator nor the agent can change them)'
# Found 22 Oct: signing ai-operator in to Claude brought along every claude.ai connector on the account (Gmail, Drive,
# Calendar, Cloudflare, Cyber Range: 133 tools), and the .mcp.json approval could not be saved because C:\ADAgent is
# read-only to ai-operator. Managed settings: connectors off, admcp approved, the login token unreadable by the agent.
$managed = 'C:\Program Files\ClaudeCode'
New-Item -ItemType Directory -Force -Path $managed | Out-Null
$json = @'
{
  "disableClaudeAiConnectors": true,
  "enabledMcpjsonServers": ["admcp"],
  "permissions": { "deny": ["Read(~/.claude/**)"] }
}
'@
[IO.File]::WriteAllText("$managed\managed-settings.json", $json)   # UTF-8 without BOM; a BOM breaks JSON parsing
"  $managed\managed-settings.json written; ai-operator can read it: " +
    [bool]((icacls $managed) -match 'BUILTIN\\Users:.*\(RX\)')

Say 'Next: sign out, sign in as KENLAB\ai-operator, then in PowerShell:'
'  irm https://claude.ai/install.ps1 | iex'
'  cd C:\ADAgent\operator'
'  claude      (sign in with your account in the browser; approve the admcp server)'
'  /mcp        (expect admcp: connected, 0 tools)'
