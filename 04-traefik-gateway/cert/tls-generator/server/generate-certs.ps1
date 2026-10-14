<#
.SYNOPSIS
    Generates Custom Internal Root CA and Wildcard TLS Certificate on Windows Server.
.DESCRIPTION
    Creates a long-lived Root CA (10 years) and issues a Wildcard Server Certificate (5 years)
    for Traefik with custom SANs.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

################################################################################
# CERTIFICATE CONFIGURATION VARIABLES (EDIT AS NEEDED)
################################################################################

# Primary Wildcard Domain & Subject
$MainDomain = "chetan.local"
$Domain = "*.${MainDomain}"
$PrimaryCN = "*.${MainDomain}"

# Additional Subject Alternative Names (SANs)
$SanDomains = @(
    "*.${MainDomain}",
    "${MainDomain}",
    "*.dev.${MainDomain}",
    "*.stage.${MainDomain}",
    "*.staging.${MainDomain}",
    "*.test.${MainDomain}",
    "*.prod.${MainDomain}",
    "in-ot-monitoring.${MainDomain}",
    "in-ot-proxy.${MainDomain}",
    "in-ot-agent.${MainDomain}",
    "in-ot-snmp.${MainDomain}",
    "in-ot-syslog.${MainDomain}",
    "localhost"
)

# Note: Binding TLS certificates to raw IP addresses is generally discouraged in enterprise
# environments because IPs can change (DHCP, network migration) and IP-based certificates
# bypass DNS governance and SNI routing. Always use proper FQDNs / domain names instead.
# If strictly needed in rare testing scenarios, you can uncomment the $SanIPs below:
# $SanIPs = @(
#     "127.0.0.1"
# )

# Validity Periods
$CaValidityDays = 3650     # 10 Years
$CertValidityDays = 1825   # 5 Years

# Certificate Subject Details
$Country = "IN"
$State = "Madhya Pradesh"
$Locality = "Bhopal"
$Organization = "Local Infra"
$OrganizationalUnit = "ArgoCD & Kubernetes"
$CaCommonName = "Local Root CA"

# Output Locations
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CaStorageDir = Join-Path $ScriptDir "..\ca-store"
$ServerCertsDir = Join-Path $ScriptDir "..\output"

################################################################################
# HELPER: FIND OPENSSL EXECUTABLE
################################################################################

function Get-OpenSslPath {
    $cmd = Get-Command openssl -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $knownPaths = @(
        "C:\Program Files\Git\usr\bin\openssl.exe",
        "C:\Program Files (x86)\Git\usr\bin\openssl.exe",
        "C:\Program Files\OpenSSL-Win64\bin\openssl.exe",
        "C:\OpenSSL-Win64\bin\openssl.exe"
    )

    foreach ($path in $knownPaths) {
        if (Test-Path $path) { return $path }
    }

    throw "OpenSSL executable not found. Please install Git for Windows or OpenSSL."
}

$OpenSSL = Get-OpenSslPath

################################################################################
# SCRIPT EXECUTION
################################################################################

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " Generating Custom Internal Root CA and Wildcard TLS Certificate" -ForegroundColor Cyan
Write-Host " Using OpenSSL at: $OpenSSL" -ForegroundColor Gray
Write-Host "=================================================================" -ForegroundColor Cyan

# Create directories
New-Item -ItemType Directory -Force -Path $CaStorageDir | Out-Null
New-Item -ItemType Directory -Force -Path $ServerCertsDir | Out-Null

$CaKey = Join-Path $CaStorageDir "rootCA.key"
$CaCert = Join-Path $CaStorageDir "rootCA.crt"
$ServerKey = Join-Path $ServerCertsDir "wildcard_.${MainDomain}.key"
$ServerCert = Join-Path $ServerCertsDir "wildcard_.${MainDomain}.crt"
$TempCsr = Join-Path $CaStorageDir "wildcard.csr"
$TempExt = Join-Path $CaStorageDir "wildcard.ext"

# ------------------------------------------------------------------------------
# 1. Generate Root CA (if it does not already exist)
# ------------------------------------------------------------------------------
if ((Test-Path $CaKey) -and (Test-Path $CaCert)) {
    Write-Host "[*] Existing Root CA found in $CaStorageDir. Reusing existing CA." -ForegroundColor Yellow
} else {
    Write-Host "[+] Generating new Root CA Private Key & Certificate..." -ForegroundColor Green
    & $OpenSSL genrsa -out $CaKey 4096
    $caSubj = "/C=$Country/ST=$State/L=$Locality/O=$Organization/OU=$OrganizationalUnit/CN=$CaCommonName"
    & $OpenSSL req -x509 -new -nodes -key $CaKey -sha256 -days $CaValidityDays -out $CaCert -subj $caSubj
    Write-Host "[+] Root CA created: $CaCert" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 2. Generate Server Private Key & CSR
# ------------------------------------------------------------------------------
Write-Host "[+] Generating Server Private Key for $Domain..." -ForegroundColor Green
& $OpenSSL genrsa -out $ServerKey 2048

Write-Host "[+] Generating Certificate Signing Request (CSR)..." -ForegroundColor Green
$serverSubj = "/C=$Country/ST=$State/L=$Locality/O=$Organization/OU=$OrganizationalUnit/CN=$PrimaryCN"
& $OpenSSL req -new -key $ServerKey -out $TempCsr -subj $serverSubj

# ------------------------------------------------------------------------------
# 3. Create OpenSSL Extensions Configuration (SAN)
# ------------------------------------------------------------------------------
$extContent = @"
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
"@

$dnsIndex = 1
foreach ($d in $SanDomains) {
    $extContent += "`nDNS.$dnsIndex = $d"
    $dnsIndex++
}

# Append IP SANs (if defined)
if ($SanIPs -and $SanIPs.Count -gt 0) {
    $ipIndex = 1
    foreach ($ip in $SanIPs) {
        $extContent += "`nIP.$ipIndex = $ip"
        $ipIndex++
    }
}

[System.IO.File]::WriteAllText($TempExt, $extContent)

# ------------------------------------------------------------------------------
# 4. Sign the Server Certificate with Root CA
# ------------------------------------------------------------------------------
Write-Host "[+] Signing Server Certificate with Root CA..." -ForegroundColor Green
& $OpenSSL x509 -req -in $TempCsr -CA $CaCert -CAkey $CaKey -CAcreateserial -out $ServerCert -days $CertValidityDays -sha256 -extfile $TempExt

# Clean up temporary files
Remove-Item -Path $TempCsr, $TempExt -Force -ErrorAction SilentlyContinue

# Copy rootCA.crt to client directory
$ClientDir = Join-Path $ScriptDir "..\client"
New-Item -ItemType Directory -Force -Path $ClientDir | Out-Null
Copy-Item -Path $CaCert -Destination (Join-Path $ClientDir "rootCA.crt") -Force

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " Certificate Generation Complete!" -ForegroundColor Green
Write-Host " Server Cert: $ServerCert"
Write-Host " Server Key : $ServerKey"
Write-Host " Root CA    : $CaCert"
Write-Host " Client CA  : $(Join-Path $ClientDir 'rootCA.crt')"
Write-Host " Validity   : $CertValidityDays days (~$([math]::Round($CertValidityDays / 365)) years)"
Write-Host "=================================================================" -ForegroundColor Cyan
