<#
.SYNOPSIS
    Deletes large image archives and chart packages (*.tar, *.tgz, *.tar.gz, *.tar.zst).

.DESCRIPTION
    Recursively scans the specified path or current repository for container image archives
    and Helm chart tarballs, displays their sizes, and deletes them safely.

.PARAMETER Path
    The target root directory to scan and clean. Defaults to the repository root where this script resides.

.PARAMETER DryRun
    Lists all matching files and calculates the total space to be reclaimed without deleting anything.

.PARAMETER Force
    Deletes files immediately without prompting for confirmation.

.EXAMPLE
    .\clean-images.ps1 -DryRun
    .\clean-images.ps1 -Force
    .\clean-images.ps1 -Path .\airgap
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [string]$Path = $PSScriptRoot,

    [Alias("d")]
    [switch]$DryRun,

    [Alias("f")]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -Path $Path)) {
    Write-Error "❌ Target directory does not exist: $Path"
    exit 1
}

$resolvedPath = (Resolve-Path -Path $Path).Path

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " 🧹 Image & Archive Cleanup Tool (PowerShell)" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "🔍 Target directory: $resolvedPath"
Write-Host "🎯 Patterns: *.tar, *.tgz, *.tar.gz, *.tar.zst (excluding .git)"
if ($DryRun) {
    Write-Host "⚠️  MODE: DRY-RUN (no files will be deleted)" -ForegroundColor Yellow
}
Write-Host "=================================================================" -ForegroundColor Cyan

# Find all files matching the target extensions, excluding .git directory
$patterns = @("*.tar", "*.tgz", "*.tar.gz", "*.tar.zst")
$matchingFiles = Get-ChildItem -Path $resolvedPath -Recurse -File -Include $patterns -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }

if (-not $matchingFiles -or $matchingFiles.Count -eq 0) {
    Write-Host ""
    Write-Host "✨ No matching image or archive files found. Everything is clean!" -ForegroundColor Green
    exit 0
}

function Format-ByteSize([long]$Bytes) {
    if ($Bytes -ge 1GB) {
        return ("{0:N2} GiB" -f ($Bytes / 1GB))
    }
    elseif ($Bytes -ge 1MB) {
        return ("{0:N2} MiB" -f ($Bytes / 1MB))
    }
    elseif ($Bytes -ge 1KB) {
        return ("{0:N2} KiB" -f ($Bytes / 1KB))
    }
    else {
        return ("$Bytes B")
    }
}

$totalBytes = 0
Write-Host ""
Write-Host ("Found {0} matching file(s):" -f $matchingFiles.Count) -ForegroundColor White
Write-Host "-----------------------------------------------------------------"

foreach ($file in $matchingFiles) {
    $totalBytes += $file.Length
    $sizeFormatted = Format-ByteSize $file.Length
    $relPath = $file.FullName.Replace($resolvedPath, "").TrimStart("\", "/")
    Write-Host ("  • {0,-60} [{1}]" -f $relPath, $sizeFormatted)
}

$totalSizeFormatted = Format-ByteSize $totalBytes
Write-Host "-----------------------------------------------------------------"
Write-Host ("📊 Total size to reclaim: {0} across {1} file(s)" -f $totalSizeFormatted, $matchingFiles.Count) -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "ℹ️  Dry-run complete. Run without -DryRun to delete these files." -ForegroundColor Yellow
    exit 0
}

if (-not $Force) {
    $confirmation = Read-Host "⚠️  Are you sure you want to permanently delete these $($matchingFiles.Count) file(s)? [y/N]"
    if ($confirmation -notmatch '^(y|yes)$') {
        Write-Host "❌ Aborted by user. No files were deleted." -ForegroundColor Red
        exit 0
    }
    Write-Host "🗑️  Deleting files..." -ForegroundColor Yellow
}

$deletedCount = 0
foreach ($file in $matchingFiles) {
    try {
        $relPath = $file.FullName.Replace($resolvedPath, "").TrimStart("\", "/")
        Remove-Item -Path $file.FullName -Force -ErrorAction Stop
        Write-Host "  ✅ Deleted: $relPath" -ForegroundColor Green
        $deletedCount++
    }
    catch {
        Write-Host "  ❌ Failed to delete $($file.FullName): $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "🎉 Cleanup completed: Successfully removed $deletedCount/$($matchingFiles.Count) files." -ForegroundColor Green
Write-Host "💾 Reclaimed approximately $totalSizeFormatted of disk space." -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
