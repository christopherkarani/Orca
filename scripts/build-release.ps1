param(
    [string]$Version = $(if ($env:AEGIS_VERSION) { $env:AEGIS_VERSION } else { "1.1.0" }),
    [string]$Commit = $(if ($env:AEGIS_COMMIT) { $env:AEGIS_COMMIT } else { "unknown" }),
    [string]$BuildDate = $(if ($env:AEGIS_BUILD_DATE) { $env:AEGIS_BUILD_DATE } else { (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }),
    [string]$DistDir = $(if ($env:AEGIS_DIST_DIR) { $env:AEGIS_DIST_DIR } else { "dist" })
)

$ErrorActionPreference = "Stop"

$targets = @(
    @{ Os = "darwin"; Arch = "amd64"; Zig = "x86_64-macos"; Ext = "tar.gz"; Bin = "aegis" },
    @{ Os = "darwin"; Arch = "arm64"; Zig = "aarch64-macos"; Ext = "tar.gz"; Bin = "aegis" },
    @{ Os = "linux"; Arch = "amd64"; Zig = "x86_64-linux"; Ext = "tar.gz"; Bin = "aegis" },
    @{ Os = "linux"; Arch = "arm64"; Zig = "aarch64-linux"; Ext = "tar.gz"; Bin = "aegis" },
    @{ Os = "windows"; Arch = "amd64"; Zig = "x86_64-windows"; Ext = "zip"; Bin = "aegis.exe" }
)

function Copy-ReleasePayload($Root) {
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Copy-Item README.md, LICENSE, SECURITY.md, CONTRIBUTING.md -Destination $Root
    Copy-Item docs, policies, schemas, fixtures, examples, packages, packaging, scripts -Destination $Root -Recurse
}

if (Test-Path -LiteralPath $DistDir) { Remove-Item -LiteralPath $DistDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

foreach ($target in $targets) {
    $artifact = "aegis-v$Version-$($target.Os)-$($target.Arch).$($target.Ext)"
    $work = Join-Path $DistDir "work/$($target.Os)-$($target.Arch)"
    $prefix = Join-Path $work "prefix"
    $root = Join-Path $work "aegis-v$Version-$($target.Os)-$($target.Arch)"

    New-Item -ItemType Directory -Force -Path $prefix, $root | Out-Null
    zig build -Dtarget=$($target.Zig) -Doptimize=ReleaseSafe -Dversion=$Version -Dcommit=$Commit -Dbuild-date=$BuildDate --prefix $prefix

    Copy-ReleasePayload $root
    New-Item -ItemType Directory -Force -Path (Join-Path $root "bin") | Out-Null
    Copy-Item -LiteralPath (Join-Path $prefix "bin/$($target.Bin)") -Destination (Join-Path $root "bin/$($target.Bin)")
    $edgeBin = if ($target.Os -eq "windows") { "aegis-edge.exe" } else { "aegis-edge" }
    Copy-Item -LiteralPath (Join-Path $prefix "bin/$edgeBin") -Destination (Join-Path $root "bin/$edgeBin")

    if ($target.Ext -eq "zip") {
        Compress-Archive -LiteralPath $root -DestinationPath (Join-Path $DistDir $artifact) -Force
    } else {
        tar -C $work -czf (Join-Path $DistDir $artifact) (Split-Path -Leaf $root)
    }
    Write-Host "Built $(Join-Path $DistDir $artifact)"
}

$checksumsPath = Join-Path $DistDir "checksums.txt"
$checksumLines = foreach ($artifact in Get-ChildItem -LiteralPath $DistDir -File | Where-Object { $_.Name -like "aegis-v*.tar.gz" -or $_.Name -like "aegis-v*.zip" } | Sort-Object Name) {
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
    name = "aegis"
    version = $Version
    generator = "scripts/build-release.ps1"
    status = "hook-only"
    note = "Phase 19 provides an SBOM hook. Replace this placeholder with CycloneDX/SPDX output in the release environment if an SBOM tool is available."
    components = @(
        [ordered]@{
            name = "aegis"
            type = "application"
            language = "zig"
            dependencies = @()
        }
    )
}
$sbom | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sbomPath -Encoding ASCII
Write-Host "Wrote $sbomPath"

if ($env:AEGIS_SIGNING_ENABLED -eq "1") {
    if (-not $env:AEGIS_SIGNING_COMMAND) {
        Write-Error "Signing requested but AEGIS_SIGNING_COMMAND is not set."
        exit 1
    }
    Invoke-Expression $env:AEGIS_SIGNING_COMMAND
} else {
    Write-Host "Signing skipped; set AEGIS_SIGNING_ENABLED=1 and AEGIS_SIGNING_COMMAND in release environments."
}
