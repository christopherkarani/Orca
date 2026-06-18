param(
    [string]$Version = $(if ($env:ORCA_VERSION) { $env:ORCA_VERSION } else { "1.1.0" }),
    [string]$Commit = $(if ($env:ORCA_COMMIT) { $env:ORCA_COMMIT } else { "unknown" }),
    [string]$BuildDate = $(if ($env:ORCA_BUILD_DATE) { $env:ORCA_BUILD_DATE } else { (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }),
    [string]$DistDir = $(if ($env:ORCA_DIST_DIR) { $env:ORCA_DIST_DIR } else { "dist" }),
    [string]$DaemonArtifactDir = $(if ($env:ORCA_DAEMON_ARTIFACT_DIR) { $env:ORCA_DAEMON_ARTIFACT_DIR } else { "" }),
    [switch]$ArchiveOnly
)

$ErrorActionPreference = "Stop"

$targets = @(
    @{ Os = "darwin"; Arch = "amd64"; Zig = "x86_64-macos"; Ext = "tar.gz"; Bin = "orca" },
    @{ Os = "darwin"; Arch = "arm64"; Zig = "aarch64-macos"; Ext = "tar.gz"; Bin = "orca" },
    @{ Os = "linux"; Arch = "amd64"; Zig = "x86_64-linux"; Ext = "tar.gz"; Bin = "orca" },
    @{ Os = "linux"; Arch = "arm64"; Zig = "aarch64-linux"; Ext = "tar.gz"; Bin = "orca" },
    @{ Os = "windows"; Arch = "amd64"; Zig = "x86_64-windows"; Ext = "zip"; Bin = "orca.exe" }
)

function Copy-ReleasePayload($Root) {
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Copy-Item README.md, LICENSE, SECURITY.md, CONTRIBUTING.md -Destination $Root
    foreach ($path in @("docs", "policies", "schemas", "fixtures", "examples", "packages", "packaging", "scripts")) {
        Copy-Item $path -Destination $Root -Recurse
    }
}

function Get-HostReleaseTarget {
    $os = if ($IsWindows -or $env:OS -eq "Windows_NT") { "windows" }
          elseif ($IsMacOS) { "darwin" }
          elseif ($IsLinux) { "linux" }
          else { $null }
    $arch = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
        ([System.Runtime.InteropServices.Architecture]::Arm64) { "arm64" }
        ([System.Runtime.InteropServices.Architecture]::X64) { "amd64" }
        default { $null }
    }
    return @{ Os = $os; Arch = $arch }
}

function Resolve-DaemonArtifact($Target) {
    $daemonName = if ($Target.Os -eq "windows") { "orca-daemon.exe" } else { "orca-daemon" }
    if ($DaemonArtifactDir) {
        $candidate = Join-Path $DaemonArtifactDir "$($Target.Os)-$($Target.Arch)\$daemonName"
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    $hostTarget = Get-HostReleaseTarget
    if ($hostTarget.Os -and $hostTarget.Arch -and $Target.Os -eq $hostTarget.Os -and $Target.Arch -eq $hostTarget.Arch) {
        $outDir = Join-Path $DistDir "daemon-artifacts"
        $bash = Get-Command bash -ErrorAction SilentlyContinue
        if (-not $bash) {
            throw "bash is required to build daemon artifacts for $($Target.Os)-$($Target.Arch); install bash or set ORCA_DAEMON_ARTIFACT_DIR"
        }
        & $bash.Source (Join-Path $PWD "scripts/build-daemon-release.sh") $Target.Os $Target.Arch $outDir | Out-Null
        $built = Join-Path $outDir "$($Target.Os)-$($Target.Arch)\$daemonName"
        if (Test-Path -LiteralPath $built) {
            return $built
        }
    }

    throw "missing staged daemon artifact for $($Target.Os)-$($Target.Arch); build it via scripts/build-daemon-release.sh or set ORCA_DAEMON_ARTIFACT_DIR"
}

if (Test-Path -LiteralPath $DistDir) { Remove-Item -LiteralPath $DistDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

foreach ($target in $targets) {
    $artifact = "orca-v$Version-$($target.Os)-$($target.Arch).$($target.Ext)"
    $work = Join-Path $DistDir "work/$($target.Os)-$($target.Arch)"
    $prefix = Join-Path $work "prefix"
    $root = Join-Path $work "orca-v$Version-$($target.Os)-$($target.Arch)"

    New-Item -ItemType Directory -Force -Path $prefix, $root | Out-Null
    zig build install-orca -Dtarget=$($target.Zig) -Doptimize=ReleaseSafe -Dversion=$Version -Dcommit=$Commit -Dbuild-date=$BuildDate --prefix $prefix

    Copy-ReleasePayload $root
    New-Item -ItemType Directory -Force -Path (Join-Path $root "bin") | Out-Null
    Copy-Item -LiteralPath (Join-Path $prefix "bin/$($target.Bin)") -Destination (Join-Path $root "bin/$($target.Bin)")
    $daemonArtifact = Resolve-DaemonArtifact $target
    $daemonName = if ($target.Os -eq "windows") { "orca-daemon.exe" } else { "orca-daemon" }
    Copy-Item -LiteralPath $daemonArtifact -Destination (Join-Path $root "bin/$daemonName")

    if ($target.Ext -eq "zip") {
        Compress-Archive -LiteralPath $root -DestinationPath (Join-Path $DistDir $artifact) -Force
    } else {
        tar -C $work -czf (Join-Path $DistDir $artifact) (Split-Path -Leaf $root)
    }
    Write-Host "Built $(Join-Path $DistDir $artifact)"
}

if ($env:ORCA_SIGNING_ENABLED -eq "1") {
    if (-not $env:ORCA_SIGNING_COMMAND) {
        Write-Error "Signing requested but ORCA_SIGNING_COMMAND is not set."
        exit 1
    }
    Invoke-Expression $env:ORCA_SIGNING_COMMAND
} else {
    Write-Host "Signing skipped; set ORCA_SIGNING_ENABLED=1 and ORCA_SIGNING_COMMAND in release environments."
}

$checksumsPath = Join-Path $DistDir "checksums.txt"
$checksumLines = foreach ($artifact in Get-ChildItem -LiteralPath $DistDir -File | Where-Object { $_.Name -like "orca-v*.tar.gz" -or $_.Name -like "orca-v*.zip" } | Sort-Object Name) {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $artifact.FullName).Hash.ToLowerInvariant()
    "$hash  $($artifact.Name)"
}
if (-not $checksumLines) {
    Write-Error "No release artifacts found in $DistDir"
    exit 1
}
$checksumLines | Set-Content -LiteralPath $checksumsPath -Encoding ASCII
Write-Host "Wrote $checksumsPath"

$sbomPath = Join-Path $DistDir "sbom.json"
$sbom = [ordered]@{
    sbom_format = "placeholder"
    name = "orca-core"
    version = $Version
    generator = "scripts/build-release.ps1"
    status = "hook-only"
    note = "Phase 19 provides an SBOM hook. Replace this placeholder with CycloneDX/SPDX output in the release environment if an SBOM tool is available."
    components = @(
        [ordered]@{
            name = "orca"
            type = "application"
            language = "zig"
            dependencies = @()
        },
        [ordered]@{
            name = "orca-daemon"
            type = "application"
            language = "rust"
            dependencies = @()
        }
    )
}
$sbom | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sbomPath -Encoding ASCII
Write-Host "Wrote $sbomPath"

if (-not $ArchiveOnly) {
    Write-Error "scripts/build-release.ps1 builds Orca archive fixtures only and does not produce release-manifest.json/package-manifests. Use scripts/build-release.sh for production release verification, or pass -ArchiveOnly for local archive smoke tests."
    exit 1
}
