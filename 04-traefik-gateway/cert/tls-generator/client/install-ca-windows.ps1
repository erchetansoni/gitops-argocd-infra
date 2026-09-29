<#
.SYNOPSIS
    Installs the Internal Root CA into the Windows Trusted Root Certification Authorities store.
.DESCRIPTION
    Must be executed with Administrator privileges.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " Installing Internal Root CA on Windows" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# Check for Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Please open PowerShell as Administrator and run the script again." -ForegroundColor Yellow
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CaCert = Join-Path $ScriptDir "rootCA.crt"

if (-not (Test-Path $CaCert)) {
    Write-Host "ERROR: Root CA certificate not found at:" -ForegroundColor Red
    Write-Host "  $CaCert" -ForegroundColor Yellow
    Write-Host "Please make sure 'rootCA.crt' is in the same directory as this script." -ForegroundColor Yellow
    exit 1
}

try {
    Write-Host "[+] Importing Root CA into 'Trusted Root Certification Authorities'..." -ForegroundColor Green
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CaCert)
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $store.Add($cert)
    $store.Close()

    Write-Host "✔ Root CA successfully installed and trusted system-wide!" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to import certificate: $_" -ForegroundColor Red
    exit 1
}

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " Complete! Please restart Google Chrome / Microsoft Edge." -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
