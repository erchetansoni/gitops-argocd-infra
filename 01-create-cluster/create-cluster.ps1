<#
.SYNOPSIS
    Automates local KinD cluster creation with ingress port mappings (80/443).

.DESCRIPTION
    Reads kind-cluster-config.yaml, confirms cluster parameters, executes 'kind create cluster',
    and waits for all kube-system control plane pods to reach Ready state.

.PARAMETER Force
    Skip confirmation prompt and create cluster immediately.

.EXAMPLE
    .\create-cluster.ps1
    .\create-cluster.ps1 -Force
#>

[CmdletBinding()]
param(
    [Alias("f")]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot
$ConfigFile = "$ScriptDir\kind-cluster-config.yaml"

if (-not (Test-Path $ConfigFile)) {
    Write-Error "[ERROR] KinD cluster config file not found at: $ConfigFile"
    exit 1
}

if (-not (Get-Command kind -ErrorAction SilentlyContinue)) {
    Write-Error "[ERROR] 'kind' CLI is not installed or not in PATH."
    exit 1
}

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Error "[ERROR] 'kubectl' CLI is not installed or not in PATH."
    exit 1
}

# Extract k8s image tag
$k8sVersion = "latest"
$imageMatch = Select-String -Path $ConfigFile -Pattern '^\s*image:\s*([^\s]+)'
if ($imageMatch) {
    $k8sVersion = ($imageMatch.Matches[0].Groups[1].Value -split ':')[-1]
}

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " [CLUSTER] Creating KinD Local Cluster (PowerShell)" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Kubernetes Version: $k8sVersion"
Write-Host "Config File:        $ConfigFile"

if (-not $Force) {
    $confirm = Read-Host "Do you want to proceed? [y/N]"
    if ($confirm -notmatch "^[yY]") {
        Write-Host "Operation canceled by user." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""
Write-Host "[1/2] Creating KinD cluster with Kubernetes $k8sVersion..." -ForegroundColor Yellow
kind create cluster --config "$ConfigFile"

Write-Host ""
Write-Host "[2/2] Waiting for all kube-system pods to be Ready..." -ForegroundColor Yellow
kubectl wait --namespace kube-system --for=condition=Ready pods --all --timeout=180s

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "[SUCCESS] KinD cluster created successfully!" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
