# ==============================================================================
# GitOps Platform - Access & Credentials Summary Tool (PowerShell)
# ==============================================================================
# Displays service URLs, login credentials, cluster status, and DNS setup.
# Usage: .\print-summary.ps1 [-FailedStep "Step Name"] [-ExitCode 1]
# ==============================================================================

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$FailedStep = "",

    [Parameter(Mandatory = $false)]
    [int]$ExitCode = 0
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# 1. Load .env if present
$EnvFile = Join-Path $ScriptDir ".env"
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
            $parts = $line.Split('=', 2)
            $k = $parts[0].Trim()
            $v = $parts[1].Trim().Trim('"').Trim("'")
            if (-not [string]::IsNullOrEmpty($k)) {
                # evaluate any simple ${VAR} expansions
                $v = [System.Text.RegularExpressions.Regex]::Replace($v, '\$\{([^}]+)\}', {
                    param($match)
                    $subVar = $match.Groups[1].Value
                    $subVal = [System.Environment]::GetEnvironmentVariable($subVar)
                    if ($subVal) { $subVal } else { $match.Value }
                })
                [System.Environment]::SetEnvironmentVariable($k, $v, "Process")
            }
        }
    }
}

$MainDomain = if ($env:MAIN_DOMAIN) { $env:MAIN_DOMAIN } else { "chetan.local" }
$ArgoCdHost = if ($env:ARGOCD_HOST) { $env:ARGOCD_HOST } else { "argocd.$MainDomain" }
$ForgejoHost = if ($env:FORGEJO_HOST) { $env:FORGEJO_HOST } else { "git.$MainDomain" }
$HarborHost = if ($env:HARBOR_HOST) { $env:HARBOR_HOST } else { "cr.$MainDomain" }

$ArgoCdNs = if ($env:ARGOCD_NAMESPACE) { $env:ARGOCD_NAMESPACE } else { "argocd" }
$ForgejoNs = if ($env:FORGEJO_NAMESPACE) { $env:FORGEJO_NAMESPACE } else { "forgejo" }
$HarborNs = if ($env:HARBOR_NAMESPACE) { $env:HARBOR_NAMESPACE } else { "harbor" }

$ForgejoUser = if ($env:FORGEJO_USER) { $env:FORGEJO_USER } else { "forgejo_admin" }
$ForgejoPass = if ($env:FORGEJO_PASS) { $env:FORGEJO_PASS } else { "Forgejo12345" }
$ForgejoRepo = if ($env:FORGEJO_REPO_NAME) { $env:FORGEJO_REPO_NAME } else { "gitops-argocd-infra" }
$HarborPass = if ($env:HARBOR_ADMIN_PASSWORD) { $env:HARBOR_ADMIN_PASSWORD } else { "Harbor12345" }

# Check cluster reachability
$K8sOnline = $false
try {
    $null = kubectl cluster-info 2>$null
    if ($LASTEXITCODE -eq 0) { $K8sOnline = $true }
} catch {
    $K8sOnline = $false
}

Write-Host ""
if ($FailedStep) {
    Write-Host "=================================================================================" -ForegroundColor Red
    Write-Host " ❌ PLATFORM ORCHESTRATION HALTED: $FailedStep" -ForegroundColor Red
    if ($ExitCode -ne 0) {
        Write-Host " ⚠️ Exit Code: $ExitCode" -ForegroundColor Yellow
    }
    Write-Host "=================================================================================" -ForegroundColor Red
    Write-Host " 💡 Troubleshooting Suggestions:" -ForegroundColor Yellow
    Write-Host "    • View recent cluster events: kubectl get events -A --sort-by=.metadata.creationTimestamp | tail -n 25"
    Write-Host "    • Check troubled pods:        kubectl get pods -A | Select-String 'Error|CrashLoopBackOff|Pending'"
    Write-Host ""
    Write-Host " ℹ️ Below is the access information for services deployed up to this point:" -ForegroundColor Cyan
    Write-Host "---------------------------------------------------------------------------------"
} else {
    Write-Host "=================================================================================" -ForegroundColor Green
    Write-Host " 🎉 GITOPS PLATFORM - ACCESS URLS & LOGIN CREDENTIALS SUMMARY" -ForegroundColor Green
    Write-Host "=================================================================================" -ForegroundColor Green
}

# 1. Argo CD
Write-Host "`n🐙 1. ARGO CD (GitOps Controller & Web UI)" -ForegroundColor Cyan
Write-Host "   -----------------------------------------------------------------------------"
$ArgoStatus = "⚪ Not yet running / not installed"
$ArgoPass = "(Initial secret rotated/deleted)"
if ($K8sOnline) {
    $argoPhase = kubectl get pods -n $ArgoCdNs -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].status.phase}' 2>$null
    if ($argoPhase) { $ArgoStatus = "🟢 Ready ($argoPhase)" }
    $b64Pwd = kubectl get secret argocd-initial-admin-secret -n $ArgoCdNs -o jsonpath="{.data.password}" 2>$null
    if ($b64Pwd) {
        $ArgoPass = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64Pwd))
    }
}
Write-Host "   Status:      $ArgoStatus"
Write-Host "   URL:         https://$ArgoCdHost"
Write-Host "   Username:    admin"
Write-Host "   Password:    $ArgoPass"
Write-Host "   CLI Login:   argocd login $ArgoCdHost --username admin --insecure"

# 2. Forgejo
Write-Host "`n🦊 2. FORGEJO (In-Cluster Git Service & Actions)" -ForegroundColor Cyan
Write-Host "   -----------------------------------------------------------------------------"
$ForgejoStatus = "⚪ Not yet running / not installed"
if ($K8sOnline) {
    $fPhase = kubectl get pods -n $ForgejoNs -l app.kubernetes.io/name=forgejo -o jsonpath='{.items[0].status.phase}' 2>$null
    if ($fPhase) { $ForgejoStatus = "🟢 Ready ($fPhase)" }
}
Write-Host "   Status:      $ForgejoStatus"
Write-Host "   Web UI:      https://$ForgejoHost"
Write-Host "   Username:    $ForgejoUser"
Write-Host "   Password:    $ForgejoPass"
Write-Host "   Clone URL:   https://${ForgejoHost}/${ForgejoUser}/${ForgejoRepo}.git"
Write-Host "   Internal:    http://forgejo-http.${ForgejoNs}.svc.cluster.local:3000/${ForgejoUser}/${ForgejoRepo}.git"

# 3. Harbor
Write-Host "`n🚢 3. HARBOR (Private Container & OCI Registry)" -ForegroundColor Cyan
Write-Host "   -----------------------------------------------------------------------------"
$HarborStatus = "⚪ Not yet running / not installed"
if ($K8sOnline) {
    $hPhase = kubectl get pods -n $HarborNs -l app=harbor,component=core -o jsonpath='{.items[0].status.phase}' 2>$null
    if ($hPhase) { $HarborStatus = "🟢 Ready ($hPhase)" }
}
Write-Host "   Status:      $HarborStatus"
Write-Host "   Web UI:      https://$HarborHost"
Write-Host "   Username:    admin"
Write-Host "   Password:    $HarborPass"
Write-Host "   Docker CLI:  docker login $HarborHost -u admin -p $HarborPass"

# 4. Traefik Gateway
Write-Host "`n🚦 4. TRAEFIK GATEWAY API" -ForegroundColor Cyan
Write-Host "   -----------------------------------------------------------------------------"
$GwStatus = "⚪ Not yet ready"
if ($K8sOnline) {
    $gw = kubectl get gateway main-gateway -n default --no-headers 2>$null
    if ($gw) {
        $rCount = (kubectl get httproute -A --no-headers 2>$null | Measure-Object).Count
        $GwStatus = "🟢 Active ('main-gateway' on Ports 80 & 443, Routes: $rCount)"
    }
}
Write-Host "   Gateway:     $GwStatus"

# 5. DNS / Hosts
Write-Host "`n🌐 5. LOCAL DNS / HOSTS RESOLUTION" -ForegroundColor Cyan
Write-Host "   -----------------------------------------------------------------------------"
Write-Host "   Ensure local domains resolve to 127.0.0.1:"
Write-Host "   • Windows (Run PowerShell as Administrator):"
Write-Host "     Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value `"127.0.0.1 $ArgoCdHost $ForgejoHost $HarborHost`"" -ForegroundColor Yellow
Write-Host ""
Write-Host "   • Linux / macOS:"
Write-Host "     echo `"127.0.0.1 $ArgoCdHost $ForgejoHost $HarborHost`" | sudo tee -a /etc/hosts" -ForegroundColor Yellow

# 6. Applications
if ($K8sOnline) {
    $appCount = (kubectl get applications -n $ArgoCdNs --no-headers 2>$null | Measure-Object).Count
    if ($appCount -gt 0) {
        Write-Host "`n📦 6. GITOPS APPLICATIONS" -ForegroundColor Cyan
        Write-Host "   -----------------------------------------------------------------------------"
        Write-Host "   Active Applications: $appCount managed by Argo CD"
    }
}

Write-Host "`n=================================================================================" -ForegroundColor Green
Write-Host " 💡 Quick Commands:"
Write-Host "    • View all pods:       kubectl get pods -A"
Write-Host "    • View all routes:     kubectl get httproute -A"
Write-Host "    • View Argo CD apps:   kubectl get applications -n $ArgoCdNs"
Write-Host "    • Re-display summary:  .\print-summary.ps1 (or ./print-summary.sh)"
Write-Host "=================================================================================" -ForegroundColor Green
Write-Host ""
