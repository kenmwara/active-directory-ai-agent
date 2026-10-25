# lab/watch-dc01.ps1: a live view of what DC01 itself records when the agent acts (the demo video, Phase 7 takes).
# The agent says what it did; this shows what the domain controller saw, independently. ON DC01, elevated PowerShell
# (the Security log needs admin):  powershell -ExecutionPolicy Bypass -File C:\Lab\watch-dc01.ps1     Ctrl+C stops it.
param([string]$Agent = 'ai-operator', [int]$PollSeconds = 2)
$ErrorActionPreference = 'Stop'
$ids = 4722, 4725, 4728, 4729, 4767, 4662
$what = @{ 4722 = 'ENABLED'; 4725 = 'DISABLED'; 4728 = 'ADDED TO GROUP'; 4729 = 'REMOVED FROM GROUP'; 4767 = 'UNLOCKED'; 4662 = 'WRITE REFUSED' }
function Field($x, $n) { ($x.Event.EventData.Data | Where-Object Name -eq $n | Select-Object -First 1).'#text' }

$Host.UI.RawUI.WindowTitle = 'DC01: what the domain controller records'
try {   # camera-ready: maximized, large Consolas (classic console host; skipped quietly anywhere else)
    Add-Type -Namespace W -Name Con -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct Font {
    public uint cbSize; public uint nFont; public short X; public short Y; public uint Family; public uint Weight;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Face; }
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern bool SetCurrentConsoleFontEx(IntPtr h, bool max, ref Font f);
'@
    $font = New-Object 'W.Con+Font'
    $font.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($font); $font.Y = 30; $font.Weight = 400; $font.Face = 'Consolas'
    [void][W.Con]::SetCurrentConsoleFontEx([W.Con]::GetStdHandle(-11), $false, [ref]$font)
    [void][W.Con]::ShowWindow([W.Con]::GetConsoleWindow(), 3)
} catch { }
Clear-Host
Write-Host ''
Write-Host '  DC01  |  what the domain controller records, live' -ForegroundColor Cyan
Write-Host "  green = done by $Agent    red = refused by AD" -ForegroundColor DarkGray
Write-Host ('  ' + '-' * 70)
$last = (Get-WinEvent -LogName Security -MaxEvents 1).RecordId
while ($true) {
    $new = @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = $ids; StartTime = (Get-Date).AddMinutes(-5) } -ErrorAction SilentlyContinue |
        Where-Object RecordId -gt $last | Sort-Object RecordId)
    foreach ($e in $new) {
        $last = [math]::Max($last, $e.RecordId)
        $failed = ($e.Keywords -band 0x10000000000000) -ne 0          # Audit Failure
        if ($e.Id -eq 4662 -and -not $failed) { continue }            # 4662: only the refused writes
        $x = [xml]$e.ToXml()
        $actor = Field $x 'SubjectUserName'
        $target = switch ($e.Id) {
            { $_ -in 4728, 4729 } { "$((Field $x 'MemberName') -replace '^CN=([^,]+),.*', '$1') -> $(Field $x 'TargetUserName')"; break }
            4662 { Field $x 'ObjectName'; break }
            default { Field $x 'TargetUserName' }
        }
        $color = if ($e.Id -eq 4662) { 'Red' } elseif ($actor -eq $Agent) { 'Green' } else { 'Gray' }
        Write-Host ('  {0:HH:mm:ss}  {1,-19} {2,-30} by {3}' -f $e.TimeCreated, $what[$e.Id], $target, $actor) -ForegroundColor $color
    }
    Start-Sleep $PollSeconds
}
