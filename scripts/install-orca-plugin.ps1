param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("opencode", "openclaw", "hermes", "hermess")]
    [string]$Host,
    [ValidateSet("project", "global")]
    [string]$Scope = "project"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")

$orcaBin = if ($env:ORCA_BIN) { $env:ORCA_BIN } else { "orca" }

if (-not (Get-Command $orcaBin -ErrorAction SilentlyContinue)) {
    & (Join-Path $repoRoot "scripts/install.ps1")
    $installDir = if ($env:ORCA_INSTALL_DIR) {
        $env:ORCA_INSTALL_DIR
    } elseif ($env:ORCA_INSTALL_DIR) {
        $env:ORCA_INSTALL_DIR
    } else {
        Join-Path $HOME ".orca\bin"
    }
    $orcaBin = Join-Path $installDir "orca.exe"
}

if (-not (Test-Path -LiteralPath $orcaBin) -and -not (Get-Command $orcaBin -ErrorAction SilentlyContinue)) {
    throw "orca binary not found after install attempt"
}

$doctorHost = if ($Host -eq "hermess") { "hermes" } else { $Host }

if ($doctorHost -eq "opencode") {
    & $orcaBin plugin install opencode --scope $Scope --yes
} elseif ($doctorHost -eq "hermes") {
    & $orcaBin plugin install hermes --yes
} else {
    & $orcaBin plugin install openclaw --yes
}

& $orcaBin plugin doctor $doctorHost
