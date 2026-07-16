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
            $Version = "1.2.0"
        }
    }
}
if (-not $BaseUrl) {
    $BaseUrl = "https://github.com/christopherkarani/Orca/releases/download/v$Version"
}

$ResourceRoot = if ($env:ORCA_RESOURCE_ROOT) { $env:ORCA_RESOURCE_ROOT } else { Join-Path $ShareDir $Version }
$CurrentLink = Join-Path $ShareDir "current"
$RuntimeDirs = @("integrations", "fixtures", "schemas", "policies")

$Quiet = ($env:ORCA_INSTALL_QUIET -eq "1")
# Errors may still use color when the host supports it; quiet only suppresses non-error UI.
$HostSupportsColor = -not $env:NO_COLOR -and ($null -ne $Host.UI.RawUI)
$UseColor = -not $Quiet -and $HostSupportsColor

function Write-Ui([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Gray) {
    if ($Quiet) { return }
    if ($UseColor) {
        Write-Host $Message -ForegroundColor $Color
    } else {
        Write-Host $Message
    }
}

function Write-HostColor([string]$Message, [ConsoleColor]$Color) {
    if ($HostSupportsColor) {
        Write-Host $Message -ForegroundColor $Color
    } else {
        Write-Host $Message
    }
}

function Write-StepDone([string]$Label, [string]$Detail = "") {
    if ($Detail) {
        Write-Ui ("  + " + $Label + "  " + $Detail) Green
    } else {
        Write-Ui ("  + " + $Label) Green
    }
}

function Write-StepActive([string]$Label) {
    Write-Ui ("  > " + $Label) Green
}

function Write-Activation {
    # Always printed (including quiet) so automation can hand off to orca env.
    Write-Host "    orca env   # then evaluate the set commands (or copy them for cmd.exe)"
}

function Fail($Message, $Remediation = $null) {
    Write-Host ""
    Write-HostColor ("  x " + $Message) Red
    if ($Remediation) {
        foreach ($line in ($Remediation -split "`n")) {
            if ($line) { Write-HostColor ("    " + $line) DarkGray }
        }
    }
    Write-Host ""
    Write-HostColor "  Docs  https://github.com/christopherkarani/Orca/blob/main/docs/install.md" DarkGray
    exit 1
}

function Detect-OS {
    if ($env:ORCA_OS_OVERRIDE) { return $env:ORCA_OS_OVERRIDE.ToLowerInvariant() }
    if ($IsWindows -or $env:OS -eq "Windows_NT") { return "windows" }
    Fail "unsupported operating system for install.ps1" "Use scripts/install.sh on macOS/Linux."
}

function Detect-Arch {
    $arch = if ($env:ORCA_ARCH_OVERRIDE) { $env:ORCA_ARCH_OVERRIDE } else { [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() }
    switch ($arch.ToLowerInvariant()) {
        "x64" { return "amd64" }
        "x86_64" { return "amd64" }
        "amd64" { return "amd64" }
        default { Fail "unsupported architecture: $arch" "Supported: amd64 (x64)." }
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
        Fail "checksums.txt not found" "Download checksums.txt with the archive and verify manually before installing."
    }
    $expected = Get-ChecksumEntry $ChecksumsPath $ArtifactName
    if (-not $expected) { Fail "no checksum entry found for $ArtifactName" "The release checksums.txt may not list this platform artifact yet." }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $ArtifactPath).Hash.ToLowerInvariant()
    if ($expected -ne $actual) {
        Fail "checksum mismatch for $ArtifactName" @"
Expected: $expected
Got:      $actual
Refuse to install a corrupted or tampered archive.
"@
    }
}

# Returns $null when path is missing or not Orca; otherwise @{ Version = <semver or $null> }.
# Matches CLI and daemon: product JSON, ^orca(-daemon)?, or a bare semver line.
function Get-ExistingOrcaInfo($Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $output = & $Path version 2>$null | Out-String
    } catch {
        return $null
    }
    if (-not ($output -match '"product"\s*:\s*"orca"|^orca(-daemon)?(\s|$)|^\d+\.\d+\.\d+')) {
        return $null
    }
    $version = $null
    $m = [regex]::Match($output, '\d+\.\d+\.\d+')
    if ($m.Success) { $version = $m.Value }
    return @{ Version = $version }
}

function Install-RuntimeAssets($ExtractRoot) {
    New-Item -ItemType Directory -Force -Path $ResourceRoot | Out-Null
    foreach ($dir in $RuntimeDirs) {
        $source = Join-Path $ExtractRoot $dir
        if (-not (Test-Path -LiteralPath $source)) {
            Fail "release archive missing runtime directory: $dir" "Re-download the official release artifact for v$Version."
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
        return
    }

    @(
        "",
        $marker,
        "`$env:ORCA_RESOURCE_ROOT = `"$TargetRoot`""
    ) | Add-Content -LiteralPath $profilePath
}

function Write-SuccessReceipt {
    param(
        [string]$PreviousVersion,
        [string]$Destination,
        [string]$DaemonDestination
    )

    if ($Quiet) {
        Write-Activation
        return
    }

    Write-Host ""
    if ($PreviousVersion -and $PreviousVersion -ne $Version -and $PreviousVersion -ne "installed") {
        Write-Ui ("  +  Orca v" + $Version + " installed  (upgraded from " + $PreviousVersion + ")") Green
    } elseif ($PreviousVersion) {
        Write-Ui ("  +  Orca v" + $Version + " reinstalled") Green
    } else {
        Write-Ui ("  +  Orca v" + $Version + " installed") Green
    }
    Write-Ui "  Daemon + runtime ready" DarkGray
    Write-Host ""
    Write-Ui "  Activate this session" White
    Write-Ui "  (InstallDir may not be on PATH yet)" DarkGray
    Write-Host ""
    Write-Activation
    Write-Host ""
    Write-Ui "  Profile exports were also written for future sessions." DarkGray
    Write-Host ""
    Write-Ui "  Then" White
    Write-Host "    orca doctor"
    Write-Host "    orca setup          # guided host wiring (default on interactive terminals)"

    Write-Host ""
    Write-Ui "  Details" DarkGray
    Write-Ui ("    binary   " + $Destination) DarkGray
    Write-Ui ("    daemon   " + $DaemonDestination) DarkGray
    Write-Ui ("    assets   " + $CurrentLink + " -> " + $ResourceRoot) DarkGray
    Write-Host ""
}

$os = Detect-OS
$arch = Detect-Arch
if ($os -ne "windows") { Fail "unsupported operating system: $os" }

$artifact = "orca-v$Version-windows-$arch.zip"
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "orca-install-$([System.Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tempDir | Out-Null

$destination = Join-Path $InstallDir "orca.exe"
$daemonDestination = Join-Path $InstallDir "orca-daemon.exe"

# Empty = fresh; semver or "installed" = existing CLI at destination.
$previousVersion = $null
$existingCli = Get-ExistingOrcaInfo $destination
if ($existingCli) {
    $previousVersion = $existingCli.Version
    if (-not $previousVersion) { $previousVersion = "installed" }
}

if (-not $Quiet) {
    Write-Host ""
    Write-Ui ("  Orca · v" + $Version) Cyan
    Write-Ui "  --------------------------------" DarkGray
    Write-Ui "  Agent runtime protection · policy + daemon" DarkGray
    Write-Host ("  Platform  " + $os + "/" + $arch)
    Write-Host ("  Target    " + $InstallDir)
    Write-Host ""
}

try {
    $artifactPath = Join-Path $tempDir $artifact
    $checksumsPath = Join-Path $tempDir "checksums.txt"

    $resolveDetail = "v" + $Version
    if ($previousVersion -and $previousVersion -ne $Version -and $previousVersion -ne "installed") {
        $resolveDetail = $resolveDetail + "; upgrading " + $previousVersion + " -> " + $Version
    } elseif ($previousVersion) {
        $resolveDetail = $resolveDetail + "; reinstall"
    }
    Write-StepDone "Resolve release" $resolveDetail

    if ($ArtifactDir) {
        $localArtifact = Join-Path $ArtifactDir $artifact
        $localChecksums = Join-Path $ArtifactDir "checksums.txt"
        if (-not (Test-Path -LiteralPath $localArtifact)) {
            Fail "artifact not found: $localArtifact" "Expected $artifact under ORCA_ARTIFACT_DIR."
        }
        if (-not (Test-Path -LiteralPath $localChecksums)) {
            Fail "checksums.txt not found in $ArtifactDir" "Place checksums.txt next to the archive for offline install."
        }
        Copy-Item -LiteralPath $localArtifact -Destination $artifactPath
        Copy-Item -LiteralPath $localChecksums -Destination $checksumsPath
        Write-StepDone "Use local artifacts" $ArtifactDir
    } else {
        Write-StepActive "Download archive"
        Invoke-WebRequest -Uri "$BaseUrl/$artifact" -OutFile $artifactPath
        Invoke-WebRequest -Uri "$BaseUrl/checksums.txt" -OutFile $checksumsPath
        Write-StepDone "Download archive" $artifact
    }

    Verify-Checksum $artifactPath $checksumsPath $artifact
    Write-StepDone "Verify SHA-256" "ok"

    Write-StepActive "Install binaries + runtime"
    Expand-Archive -LiteralPath $artifactPath -DestinationPath $tempDir -Force
    $extractRoot = Get-ChildItem -LiteralPath $tempDir -Directory | Where-Object { $_.Name -like "orca-v*" } | Select-Object -First 1
    if (-not $extractRoot) {
        Fail "artifact did not contain an extracted release root" "Unexpected archive layout for $artifact."
    }
    $binary = Get-ChildItem -LiteralPath $extractRoot.FullName -Recurse -File -Filter "orca.exe" | Select-Object -First 1
    if (-not $binary) {
        Fail "artifact did not contain orca.exe" "Unexpected archive layout for $artifact."
    }
    $daemonBinary = Get-ChildItem -LiteralPath $extractRoot.FullName -Recurse -File -Filter "orca-daemon.exe" | Select-Object -First 1
    if (-not $daemonBinary) {
        Fail "artifact did not contain orca-daemon.exe" "Unexpected archive layout for $artifact."
    }

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    if ((Test-Path -LiteralPath $destination) -and $env:ORCA_INSTALL_FORCE -ne "1") {
        if (-not (Get-ExistingOrcaInfo $destination)) {
            Fail "refusing to overwrite non-Orca file at $destination" "Set ORCA_INSTALL_FORCE=1 to replace it, or choose another ORCA_INSTALL_DIR."
        }
    }
    if ((Test-Path -LiteralPath $daemonDestination) -and $env:ORCA_INSTALL_FORCE -ne "1") {
        if (-not (Get-ExistingOrcaInfo $daemonDestination)) {
            Fail "refusing to overwrite non-Orca file at $daemonDestination" "Set ORCA_INSTALL_FORCE=1 to replace it, or choose another ORCA_INSTALL_DIR."
        }
    }

    Copy-Item -LiteralPath $binary.FullName -Destination $destination -Force
    Copy-Item -LiteralPath $daemonBinary.FullName -Destination $daemonDestination -Force
    Install-RuntimeAssets $extractRoot.FullName
    Write-StepDone "Install binaries + runtime" "orca.exe, orca-daemon.exe, assets"

    Ensure-ResourceRootEntry $CurrentLink
    Write-StepDone "Configure shell" "ORCA_RESOURCE_ROOT"

    Write-SuccessReceipt -PreviousVersion $previousVersion -Destination $destination -DaemonDestination $daemonDestination
} finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
