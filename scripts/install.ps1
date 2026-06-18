param(
    [string]$Version,
    [string]$BaseUrl = $env:ORCA_BASE_URL,
    [string]$InstallDir = $(if ($env:ORCA_INSTALL_DIR) { $env:ORCA_INSTALL_DIR } else { Join-Path $HOME ".orca\bin" }),
    [string]$ShareDir = $(if ($env:ORCA_SHARE_DIR) { $env:ORCA_SHARE_DIR } else { Join-Path $HOME ".orca\share" }),
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
            $Version = "1.1.5"
        }
    }
}
if (-not $BaseUrl) {
    $BaseUrl = "https://github.com/christopherkarani/Orca/releases/download/v$Version"
}

$ResourceRoot = if ($env:ORCA_RESOURCE_ROOT) { $env:ORCA_RESOURCE_ROOT } else { Join-Path $ShareDir $Version }
$CurrentLink = Join-Path $ShareDir "current"
$RuntimeDirs = @("integrations", "fixtures", "schemas", "policies")

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

function Test-ExistingOrcaDaemon($Path) {
    try {
        $output = (& $Path version 2>$null | Out-String).Trim()
    } catch {
        return $false
    }
    return [bool]($output -match '^\d+\.\d+\.\d+')
}

function Install-RuntimeAssets($ExtractRoot) {
    New-Item -ItemType Directory -Force -Path $ResourceRoot | Out-Null
    foreach ($dir in $RuntimeDirs) {
        $source = Join-Path $ExtractRoot $dir
        if (-not (Test-Path -LiteralPath $source)) {
            Fail "release archive missing runtime directory: $dir"
        }
        $dest = Join-Path $ResourceRoot $dir
        if (Test-Path -LiteralPath $dest) {
            Remove-Item -LiteralPath $dest -Recurse -Force
        }
        Copy-Item -LiteralPath $source -Destination $dest -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $ShareDir | Out-Null
    if (Test-Path -LiteralPath $CurrentLink) {
        Remove-Item -LiteralPath $CurrentLink -Recurse -Force -ErrorAction SilentlyContinue
    }
    cmd /c mklink /J "$CurrentLink" "$ResourceRoot"
    if ($LASTEXITCODE -ne 0) {
        Fail "failed to create junction $CurrentLink -> $ResourceRoot (mklink exit code $LASTEXITCODE)"
    }
}

function Ensure-ResourceRootEntry($TargetRoot) {
    $profilePath = if ($PROFILE) { $PROFILE } else { Join-Path $HOME "Documents\PowerShell\Microsoft.PowerShell_profile.ps1" }
    $marker = "# Orca runtime assets"
    $profileDir = Split-Path -Parent $profilePath
    if ($profileDir -and -not (Test-Path -LiteralPath $profileDir)) {
        New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    }

    if ((Test-Path -LiteralPath $profilePath) -and (Select-String -LiteralPath $profilePath -Pattern [regex]::Escape($marker) -Quiet)) {
        $lines = Get-Content -LiteralPath $profilePath
        $updated = New-Object System.Collections.Generic.List[string]
        $skipNextResourceRoot = $false
        foreach ($line in $lines) {
            if ($line -eq $marker) {
                [void]$updated.Add($line)
                [void]$updated.Add("`$env:ORCA_RESOURCE_ROOT = `"$TargetRoot`"")
                $skipNextResourceRoot = $true
                continue
            }
            if ($skipNextResourceRoot -and $line -match '^\$env:ORCA_RESOURCE_ROOT\s*=') {
                continue
            }
            if ($skipNextResourceRoot -and [string]::IsNullOrWhiteSpace($line)) {
                $skipNextResourceRoot = $false
            }
            [void]$updated.Add($line)
        }
        Set-Content -LiteralPath $profilePath -Value $updated
        Write-Host "Updated ORCA_RESOURCE_ROOT=$TargetRoot in $profilePath"
        return
    }

    @(
        "",
        $marker,
        "`$env:ORCA_RESOURCE_ROOT = `"$TargetRoot`""
    ) | Add-Content -LiteralPath $profilePath
    Write-Host "Added ORCA_RESOURCE_ROOT=$TargetRoot to $profilePath"
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
    $extractRoot = Get-ChildItem -LiteralPath $tempDir -Directory | Where-Object { $_.Name -like "orca-v*" } | Select-Object -First 1
    if (-not $extractRoot) { Fail "artifact did not contain an extracted release root" }
    $binary = Get-ChildItem -LiteralPath $extractRoot.FullName -Recurse -File -Filter "orca.exe" | Select-Object -First 1
    if (-not $binary) { Fail "artifact did not contain orca.exe" }
    $daemonBinary = Get-ChildItem -LiteralPath $extractRoot.FullName -Recurse -File -Filter "orca-daemon.exe" | Select-Object -First 1
    if (-not $daemonBinary) { Fail "artifact did not contain orca-daemon.exe" }

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $destination = Join-Path $InstallDir "orca.exe"
    $daemonDestination = Join-Path $InstallDir "orca-daemon.exe"
    if ((Test-Path -LiteralPath $destination) -and $env:ORCA_INSTALL_FORCE -ne "1") {
        if (-not (Test-ExistingOrca $destination)) {
            Fail "refusing to overwrite non-Orca file at $destination; set ORCA_INSTALL_FORCE=1 to replace it"
        }
    }
    if ((Test-Path -LiteralPath $daemonDestination) -and $env:ORCA_INSTALL_FORCE -ne "1") {
        if (-not (Test-ExistingOrcaDaemon $daemonDestination)) {
            Fail "refusing to overwrite non-Orca file at $daemonDestination; set ORCA_INSTALL_FORCE=1 to replace it"
        }
    }

    Copy-Item -LiteralPath $binary.FullName -Destination $destination -Force
    Copy-Item -LiteralPath $daemonBinary.FullName -Destination $daemonDestination -Force
    Install-RuntimeAssets $extractRoot.FullName

    Write-Host "Installed Orca to $destination"
    Write-Host "Installed Orca daemon to $daemonDestination"
    Write-Host "Installed runtime assets to $ResourceRoot"
    Write-Host "Current runtime link: $CurrentLink -> $ResourceRoot"
    Write-Host "ORCA_RESOURCE_ROOT=$CurrentLink"
    Ensure-ResourceRootEntry $CurrentLink
    Write-Host ""
    Write-Host "To use orca in this PowerShell session (before restarting or reloading `$PROFILE), run:"
    Write-Host "  orca env   # then evaluate the set commands (or copy them for cmd.exe)"
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  orca --version"
    Write-Host "  orca doctor"
    Write-Host "  orca setup          # guided interactive host selection (default on interactive terminals)"
    Write-Host "  (optional) orca plugin list"
} finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
