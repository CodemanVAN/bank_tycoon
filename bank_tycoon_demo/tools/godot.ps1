# Serialized Godot 4.7.2 runner for the Starway Bank demo.
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GodotArgs)

$godot = "D:\project\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$projectDir = Split-Path -Parent $PSScriptRoot

$finalArgs = @("--headless", "--path", $projectDir)
if ($GodotArgs) { $finalArgs += $GodotArgs }
if ($GodotArgs -contains "--import" -and -not ($GodotArgs -contains "--quit")) { $finalArgs += "--quit" }

$mutex = New-Object System.Threading.Mutex($false, "Global\StarwayBankGodotRunner")
$acquired = $false
$code = 1
try {
    try { $acquired = $mutex.WaitOne([TimeSpan]::FromMinutes(15)) }
    catch [System.Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) { Write-Error "[godot.ps1] Timed out waiting for Godot mutex"; exit 2 }
    $ErrorActionPreference = "Continue"
    & $godot @finalArgs
    $code = $LASTEXITCODE
}
finally {
    if ($acquired) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
exit $code
