# lab/run-checks-as-operator.ps1 (Phase 3 + 4 checks): run ON CLIENT01 signed in as KENLAB\ai-operator, the agent's own
# identity, in a normal (not elevated) PowerShell:
#     powershell -ExecutionPolicy Bypass -File C:\ADAgent\lab\run-checks-as-operator.ps1
# Reads the targets phase34-host.ps1 left in C:\Users\Public\Documents\admcp\targets.json, runs the delegation matrix and
# every tool over stdio, and writes one report there for the laptop to collect (phase34-host.ps1 -Step Evidence).
$ErrorActionPreference = 'Stop'
$out = 'C:\Users\Public\Documents\admcp'
$t = Get-Content "$out\targets.json" -Raw | ConvertFrom-Json
& {
    "== whoami: $(whoami)   start $(Get-Date -Format o)"
    "== DC locator (needs a DC running AD Web Services)"
    cmd /c "nltest /dsgetdc:ad.kenmwara.com /ws 2>&1"   # via cmd: nltest's stderr must not stop the run (EAP Stop)
    "== 4.2 delegation matrix (InUser=$($t.InUser) Member=$($t.Member) InGroup=$($t.InGroup) OutUser=$($t.OutUser) OutGroup=$($t.OutGroup))"
    & "$PSScriptRoot\test-delegation.ps1" -InUser $t.InUser -OutUser $t.OutUser -InGroup $t.InGroup -OutGroup $t.OutGroup -Member $t.Member |
        Out-String -Width 250
    "== 3.x tools over stdio"
    Push-Location 'C:\ADAgent'
    # Continue: a native program's stderr must not stop the run (the server's own log goes to run_tools.server.log)
    $ErrorActionPreference = 'Continue'
    try { & 'C:\ADAgent\.venv\Scripts\python.exe' tests\run_tools.py "$out\targets.json" 2>&1 | Out-String -Width 250 } finally { Pop-Location }
    "== end $(Get-Date -Format o)"
} *>&1 | Tee-Object -FilePath "$out\phase34-report.txt"
"report written: $out\phase34-report.txt"
