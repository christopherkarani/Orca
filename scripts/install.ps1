param(
    [string]$Version,
    [string]$BaseUrl = $env:ORCA_BASE_URL,
    [string]$InstallDir = $(if ($env:ORCA_INSTALL_DIR) { $env:ORCA_INSTALL_DIR } else { Join-Path $HOME ".orca\bin" }),
    [string]$ArtifactDir = $env:ORCA_ARTIFACT_DIR
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Version) {
    if ($env:ORCA_VERSION) {
        $Version = $env:ORCA_VERSION
    } else {
        $defaultVersionPath = Join-Path (Resolve-Path (Join-Path $scriptDir "..")) "VERSION"
        if (Test-Path -LiteralPath $defaultVersionPath) {
            $Version = (Get-Content -LiteralPath $defaultVersionPath -TotalCount 1).Trim()
        } else {
            $Version = "1.1.4"
        }
    }
}
if (-not $BaseUrl) {
    $BaseUrl = "https://github.com/christopherkarani/Orca/releases/download/v$Version"
}

function Fail($Message) {
    Write-Error "orca install: $Message"
    exit 1
}

function Detect-OS {
    if ($env:ORCA_OS_OVERRIDE) { return $env:ORCA_OS_OVERRIDE.ToLowerInvariant() }
    if ($IsWindows -or $env:OS -eq "Windows_NT") { return "windows" }
    Fail "unsupported operating system for install.ps1"
}

function Detect-Arch {
    $arch = if ($env:ORCA_ARCH_OVERRIDE) { $env:ORCA_ARCH_OVERRIDE } else { [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() }
    switch ($arch.ToLowerInvariant()) {
        "x64" { return "amd64" }
        "x86_64" { return "amd64" }
        "amd64" { return "amd64" }
        default { Fail "unsupported architecture: $arch" }
    }
}

function Get-ChecksumEntry($ChecksumsPath, $ArtifactName) {
    foreach ($line in Get-Content -LiteralPath $ChecksumsPath) {
        $parts = $line -split "\s+"
        if ($parts.Length -ge 2 -and $parts[1] -eq $ArtifactName) {
            return $parts[0].ToLowerInvariant()
        }
    }
    return $null
}

function Verify-Checksum($ArtifactPath, $ChecksumsPath, $ArtifactName) {
    if (-not (Test-Path -LiteralPath $ChecksumsPath)) {
        Fail "checksums.txt not found; download it and verify manually before installing"
    }
    $expected = Get-ChecksumEntry $ChecksumsPath $ArtifactName
    if (-not $expected) { Fail "no checksum entry found for $ArtifactName" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $ArtifactPath).Hash.ToLowerInvariant()
    if ($expected -ne $actual) { Fail "checksum mismatch for $ArtifactName" }
}

function Test-ExistingOrca($Path) {
    try {
        $output = & $Path version 2>$null | Out-String
    } catch {
        return $false
    }
    return [bool]($output -match '"product"\s*:\s*"orca"|^orca(\s|$)')
}

$os = Detect-OS
$arch = Detect-Arch
if ($os -ne "windows") { Fail "unsupported operating system: $os" }

$artifact = "orca-v$Version-windows-$arch.zip"
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "orca-install-$([System.Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tempDir | Out-Null

try {
    $artifactPath = Join-Path $tempDir $artifact
    $checksumsPath = Join-Path $tempDir "checksums.txt"

    if ($ArtifactDir) {
        $localArtifact = Join-Path $ArtifactDir $artifact
        $localChecksums = Join-Path $ArtifactDir "checksums.txt"
        if (-not (Test-Path -LiteralPath $localArtifact)) { Fail "artifact not found: $localArtifact" }
        if (-not (Test-Path -LiteralPath $localChecksums)) { Fail "checksums.txt not found in $ArtifactDir" }
        Copy-Item -LiteralPath $localArtifact -Destination $artifactPath
        Copy-Item -LiteralPath $localChecksums -Destination $checksumsPath
    } else {
        Invoke-WebRequest -Uri "$BaseUrl/$artifact" -OutFile $artifactPath
        Invoke-WebRequest -Uri "$BaseUrl/checksums.txt" -OutFile $checksumsPath
    }

    Verify-Checksum $artifactPath $checksumsPath $artifact
    Expand-Archive -LiteralPath $artifactPath -DestinationPath $tempDir -Force
    $binary = Get-ChildItem -LiteralPath $tempDir -Recurse -File -Filter "orca.exe" | Select-Object -First 1
    if (-not $binary) { Fail "artifact did not contain orca.exe" }

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $destination = Join-Path $InstallDir "orca.exe"
    if ((Test-Path -LiteralPath $destination) -and $env:ORCA_INSTALL_FORCE -ne "1") {
        if (-not (Test-ExistingOrca $destination)) {
            Fail "refusing to overwrite non-Orca file at $destination; set ORCA_INSTALL_FORCE=1 to replace it"
        }
    }

    Copy-Item -LiteralPath $binary.FullName -Destination $destination -Force
    Write-Host "Installed Orca to $destination"
    Write-Host "Next steps:"
    Write-Host "  $destination version"
    Write-Host "  $destination doctor"
    Write-Host "  $destination init --preset generic-agent"
} finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
