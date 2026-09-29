<#
.SYNOPSIS
    Removes the Internal Root CA from the Windows Trusted Root Certification Authorities store.
.DESCRIPTION
    Must be executed with Administrator privileges.
#>

[CmdletBinding()]
param(
    [string]$CaCommonName = "Avgol Internal Root CA"
)

$ErrorActionPreference = "Stop"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " Removing Internal Root CA from Windows Trust Store" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# Check for Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    exit 1
}

try {
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    
    $certs = $store.Certificates | Where-Object { $_.Subject -like "*CN=$CaCommonName*" }

    if ($certs.Count -eq 0) {
        Write-Host "[*] No Root CA matching '$CaCommonName' was found in the store." -ForegroundColor Yellow
    } else {
        foreach ($cert in $certs) {
            Write-Host "[+] Removing certificate: $($cert.Subject)" -ForegroundColor Green
            $store.Remove($cert)
        }
        Write-Host "✔ Root CA successfully removed from Windows Trusted Roots!" -ForegroundColor Green
    }
    
    $store.Close()
} catch {
    Write-Host "ERROR: Failed to remove certificate: $_" -ForegroundColor Red
    exit 1
}

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " Complete! Please restart Google Chrome / Microsoft Edge." -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
