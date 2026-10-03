<#
.SYNOPSIS
    Pre-loads all platform container images into the local KinD cluster.

.DESCRIPTION
    Reads the container image inventory from airgap/images.yaml, checks local Docker cache,
    optionally pulls missing images, and loads them directly into the KinD cluster node(s)
    using 'kind load docker-image' or 'kind load image-archive'.

.PARAMETER ClusterName
    The target KinD cluster name. Defaults to 'gitops-demo-cluster'.

.PARAMETER Pull
    Automatically pulls missing images from remote registries before loading.

.PARAMETER Archive
    Loads directly from a tarball archive file (e.g. airgap/airgap-images.tar).

.PARAMETER ListOnly
    Lists all platform images and their local availability in Docker daemon without loading.

.EXAMPLE
    .\load-images-to-kind.ps1
    .\load-images-to-kind.ps1 -Pull
    .\load-images-to-kind.ps1 -Archive ..\airgap\airgap-images.tar
    .\load-images-to-kind.ps1 -ListOnly
#>

[CmdletBinding()]
param(
    [Alias("n")]
    [string]$ClusterName = "gitops-demo-cluster",

    [Alias("p")]
    [switch]$Pull,

    [Alias("a")]
    [string]$Archive,

    [Alias("l")]
    [switch]$ListOnly
)

$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot
$RepoRoot = (Resolve-Path "$ScriptDir\..").Path
$ImagesFile = "$RepoRoot\airgap\images.yaml"
$ConfigFile = "$ScriptDir\kind-cluster-config.yaml"

# Auto-detect cluster name from config file if available and not overridden
if ($PSBoundParameters.ContainsKey('ClusterName') -eq $false -and (Test-Path $ConfigFile)) {
    $cfgMatch = Select-String -Path $ConfigFile -Pattern '^\s*name:\s*([^\s]+)'
    if ($cfgMatch) {
        $ClusterName = $cfgMatch.Matches[0].Groups[1].Value
    }
}

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " [KIN-LOAD] KinD Container Image Pre-Loader (PowerShell)" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Target Cluster: $ClusterName"

# Check kind CLI
if (-not (Get-Command kind -ErrorAction SilentlyContinue)) {
    Write-Error "[ERROR] 'kind' CLI is not installed or not in PATH."
    exit 1
}

# Check docker CLI
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "[ERROR] 'docker' CLI is not installed or not in PATH."
    exit 1
}

# Verify cluster exists
$existingClusters = kind get clusters 2>$null
if (-not ($existingClusters -contains $ClusterName)) {
    Write-Error "[ERROR] KinD cluster '$ClusterName' does not exist! Please create it first using create-cluster.sh or kind create cluster."
    exit 1
}

# MODE 1: Load from Archive
if ($Archive) {
    if (-not (Test-Path $Archive)) {
        Write-Error "[ERROR] Archive file not found: $Archive"
        exit 1
    }
    $resolvedArchive = (Resolve-Path $Archive).Path
    Write-Host "[ARCHIVE] Loading container images from archive: $resolvedArchive..." -ForegroundColor Yellow
    kind load image-archive "$resolvedArchive" --name "$ClusterName"
    Write-Host "[OK] All images from archive successfully loaded into KinD cluster '$ClusterName'!" -ForegroundColor Green
    exit 0
}

# MODE 2: Load from images.yaml inventory
if (-not (Test-Path $ImagesFile)) {
    Write-Error "[ERROR] Images inventory file not found at: $ImagesFile"
    exit 1
}

Write-Host "[INFO] Reading image inventory from: airgap/images.yaml"
$images = @()
Get-Content $ImagesFile | ForEach-Object {
    if ($_ -match '^\s*image:\s*"?([^"\s]+)"?') {
        $images += $matches[1]
    }
}

if ($images.Count -eq 0) {
    Write-Error "[ERROR] No images found in $ImagesFile."
    exit 1
}

Write-Host "[INFO] Found $($images.Count) platform images in inventory."
Write-Host ""

Write-Host "[INFO] Querying local Docker daemon for cached images..."
$localImages = @(docker images --format "{{.Repository}}:{{.Tag}}")

$presentImages = @()
$missingImages = @()

foreach ($img in $images) {
    $stripped = $img -replace '^docker\.io/', ''
    if ($localImages -contains $img) {
        $presentImages += $img
        if ($ListOnly) { Write-Host "  [+] Present: $img" -ForegroundColor Green }
    } elseif ($localImages -contains $stripped) {
        $presentImages += $stripped
        if ($ListOnly) { Write-Host "  [+] Present: $stripped (matches $img)" -ForegroundColor Green }
    } else {
        $missingImages += $img
        if ($ListOnly) { Write-Host "  [-] Missing: $img" -ForegroundColor Red }
    }
}

if ($ListOnly) {
    Write-Host ""
    Write-Host "Summary: $($presentImages.Count) present locally, $($missingImages.Count) missing from Docker daemon." -ForegroundColor Cyan
    exit 0
}

# Handle missing images
if ($missingImages.Count -gt 0) {
    Write-Host "[WARN] Found $($missingImages.Count) image(s) missing from local Docker cache:" -ForegroundColor Yellow
    foreach ($m in $missingImages) {
        Write-Host "   - $m"
    }
    Write-Host ""

    $shouldPull = $Pull
    if (-not $shouldPull) {
        $response = Read-Host "Would you like to pull missing images now? [y/N]"
        if ($response -match "^[yY]") {
            $shouldPull = $true
        }
    }

    if ($shouldPull) {
        Write-Host "[PULL] Pulling missing images from remote registries..." -ForegroundColor Yellow
        foreach ($m in $missingImages) {
            Write-Host "   Downloading: $m"
            docker pull $m
            $presentImages += $m
        }
        $missingImages = @()
    } else {
        Write-Host "[INFO] Continuing with $($presentImages.Count) available image(s)..." -ForegroundColor Gray
    }
}

if ($presentImages.Count -eq 0) {
    Write-Error "[ERROR] No images available to load into KinD."
    exit 1
}

Write-Host ""
Write-Host "[LOAD] Loading $($presentImages.Count) image(s) into KinD cluster '$ClusterName'..." -ForegroundColor Green
Write-Host "Please wait (this may take 1-3 minutes depending on disk speed)..." -ForegroundColor Gray

# Load in batches of 5
$batchSize = 5
for ($i = 0; $i -lt $presentImages.Count; $i += $batchSize) {
    $count = [Math]::Min($batchSize, $presentImages.Count - $i)
    $batch = $presentImages[$i..($i + $count - 1)]
    $endNum = $i + $count
    Write-Host "   Loading batch ($($i + 1)-$endNum of $($presentImages.Count)):" -ForegroundColor Cyan
    foreach ($b in $batch) {
        Write-Host "      - $b" -ForegroundColor Gray
    }
    kind load docker-image @batch --name "$ClusterName"
}

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "[SUCCESS] Successfully loaded $($presentImages.Count) images into KinD '$ClusterName'!" -ForegroundColor Green
Write-Host "   All pods (Traefik, cert-manager, Metrics Server, Argo CD, Harbor)" -ForegroundColor Green
Write-Host "   will now start instantly without network delays or image pull timeouts." -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
