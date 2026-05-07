param(
    [string]$Version = $(if ($env:AEGIS_VERSION) { $env:AEGIS_VERSION } else { "0.19.0-dev" }),
    [string]$BaseUrl = $(if ($env:AEGIS_BASE_URL) { $env:AEGIS_BASE_URL } else { "https://github.com/chriskarani/aegis/releases/download/v$($env:AEGIS_VERSION)" }),
    [string]$InstallDir = $(if ($env:AEGIS_INSTALL_DIR) { $env:AEGIS_INSTALL_DIR } else { Join-Path $HOME ".aegis\bin" }),
    [string]$ArtifactDir = $env:AEGIS_ARTIFACT_DIR
)

$ErrorActionPreference = "Stop"
if (-not $env:AEGIS_VERSION -and $BaseUrl -like "*`$(`$env:AEGIS_VERSION)*") {
    $BaseUrl = "https://github.com/chriskarani/aegis/releases/download/v$Version"
}

function Fail($Message) {
    Write-Error "aegis install: $Message"
    exit 1
}

function Detect-OS {
    if ($env:AEGIS_OS_OVERRIDE) { return $env:AEGIS_OS_OVERRIDE.ToLowerInvariant() }
    if ($IsWindows -or $env:OS -eq "Windows_NT") { return "windows" }
    Fail "unsupported operating system for install.ps1"
}

function Detect-Arch {
    $arch = if ($env:AEGIS_ARCH_OVERRIDE) { $env:AEGIS_ARCH_OVERRIDE } else { [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() }
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

$os = Detect-OS
$arch = Detect-Arch
if ($os -ne "windows") { Fail "unsupported operating system: $os" }

$artifact = "aegis-v$Version-windows-$arch.zip"
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "aegis-install-$PID"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

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
    $binary = Get-ChildItem -LiteralPath $tempDir -Recurse -File -Filter "aegis.exe" | Select-Object -First 1
    if (-not $binary) { Fail "artifact did not contain aegis.exe" }

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $destination = Join-Path $InstallDir "aegis.exe"
    if ((Test-Path -LiteralPath $destination) -and $env:AEGIS_INSTALL_FORCE -ne "1") {
        try {
            & $destination version *> $null
        } catch {
            Fail "refusing to overwrite non-Aegis file at $destination; set AEGIS_INSTALL_FORCE=1 to replace it"
        }
    }

    Copy-Item -LiteralPath $binary.FullName -Destination $destination -Force
    Write-Host "Installed Aegis to $destination"
    Write-Host "Next steps:"
    Write-Host "  $destination version"
    Write-Host "  $destination doctor"
    Write-Host "  $destination init --preset generic-agent"
} finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
