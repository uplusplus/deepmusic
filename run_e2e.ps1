#!/usr/bin/env pw1
# DeepMusic E2E Test Runner
# 用法: .\run_e2e.ps1 [test_name]
#   test_name: pagination_test (默认) 或 app_test

param(
    [string]$TestName = "pagination_test",
    [string]$FlutterPath = "D:\08_ai\sdk\flutter\bin\flutter.bat"
)

$ErrorActionPreference = "Stop"
$TestDir = "$PSScriptRoot\mobile"
$ApkPath = "$TestDir\build\app\outputs\flutter-apk\app-debug.apk"

Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
Write-Host " DeepMusic E2E Test Runner" -ForegroundColor Cyan
Write-Host " Test: $TestName" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan

# Step 1: Check device
Write-Host "`n[1/4] Checking device..." -ForegroundColor Yellow
$devices = & adb devices 2>&1 | Select-String "device$"
if (-not $devices) {
    Write-Host "ERROR: No device connected!" -ForegroundColor Red
    exit 1
}
Write-Host "  ✅ Device connected" -ForegroundColor Green

# Step 2: Build if needed
Write-Host "`n[2/4] Building APK..." -ForegroundColor Yellow
if (-not (Test-Path $ApkPath) -or (Get-Item $ApkPath).LastWriteTime -lt (Get-Date).AddMinutes(-5)) {
    Push-Location $TestDir
    & $FlutterPath build apk --debug 2>&1 | Out-Null
    Pop-Location
    Write-Host "  ✅ APK built" -ForegroundColor Green
} else {
    Write-Host "  ✅ APK up to date" -ForegroundColor Green
}

# Step 3: Run integration test
Write-Host "`n[3/4] Running integration test: $TestName..." -ForegroundColor Yellow
Push-Location $TestDir
& $FlutterPath test "integration_test\$TestName.dart" -d $(adb devices | Select-String "device$" | ForEach-Object { ($_ -split "`t")[0] })
$testResult = $LASTEXITCODE
Pop-Location

# Step 4: Collect logs
Write-Host "`n[4/4] Collecting logs..." -ForegroundColor Yellow
$logFile = "$TestDir\e2e_log_$TestName_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
adb logcat -d | Select-String -Pattern "\[E2E\]|\[Pagination\]|\[OSMD\]|\[PERF\]" | Out-File -FilePath $logFile -Encoding utf8
Write-Host "  📄 Logs saved to: $logFile" -ForegroundColor Cyan

if ($testResult -eq 0) {
    Write-Host "`n═══════════════════════════════════════" -ForegroundColor Green
    Write-Host " ✅ TEST PASSED" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════" -ForegroundColor Green
} else {
    Write-Host "`n═══════════════════════════════════════" -ForegroundColor Red
    Write-Host " ❌ TEST FAILED (exit code: $testResult)" -ForegroundColor Red
    Write-Host "═══════════════════════════════════════" -ForegroundColor Red
}

exit $testResult
