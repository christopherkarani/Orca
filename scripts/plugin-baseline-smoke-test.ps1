# Aegis Plugin Baseline Smoke Test
# Safe checks only. No drone hardware. No network. No secrets.

$ErrorActionPreference = "Stop"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$REPO_ROOT = Resolve-Path (Join-Path $SCRIPT_DIR "..")
$AEGIS = Join-Path $REPO_ROOT "zig-out\bin\aegis.exe"
$AEGIS_EDGE = Join-Path $REPO_ROOT "zig-out\bin\aegis-edge.exe"

$ERRORS = 0

function Log-Info($msg) { Write-Host "[INFO]  $msg" }
function Log-Pass($msg) { Write-Host "[PASS]  $msg" }
function Log-Fail($msg) { Write-Host "[FAIL]  $msg"; $script:ERRORS++ }

Push-Location $REPO_ROOT

try {
    Log-Info "=== Aegis Plugin Baseline Smoke Test ==="
    Log-Info "Repo: $REPO_ROOT"
    Log-Info "Date: $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
    Write-Host ""

    # 1. Build
    Log-Info "Running zig build..."
    try {
        $null = zig build 2>$null
        Log-Pass "zig build"
    } catch {
        Log-Fail "zig build"
    }
    Write-Host ""

    # 2. Tests
    Log-Info "Running zig build test..."
    try {
        $null = zig build test 2>$null
        Log-Pass "zig build test"
    } catch {
        Log-Fail "zig build test"
    }
    Write-Host ""

    # 3. CLI smoke tests
    Log-Info "Running CLI smoke tests..."

    if (Test-Path $AEGIS) {
        try { $null = & $AEGIS --help 2>$null; Log-Pass "aegis --help" } catch { Log-Fail "aegis --help" }
        try { $null = & $AEGIS version 2>$null; Log-Pass "aegis version" } catch { Log-Fail "aegis version" }
        try { $null = & $AEGIS doctor 2>$null; Log-Pass "aegis doctor" } catch { Log-Fail "aegis doctor" }
        try { $null = & $AEGIS redteam --ci 2>$null; Log-Pass "aegis redteam --ci" } catch { Log-Fail "aegis redteam --ci" }
    } else {
        Log-Fail "aegis binary not found at $AEGIS"
    }
    Write-Host ""

    # 4. Edge CLI smoke tests
    Log-Info "Running Edge CLI smoke tests..."

    if (Test-Path $AEGIS_EDGE) {
        try { $null = & $AEGIS_EDGE --help 2>$null; Log-Pass "aegis-edge --help" } catch { Log-Fail "aegis-edge --help" }
        try { $null = & $AEGIS_EDGE doctor 2>$null; Log-Pass "aegis-edge doctor" } catch { Log-Fail "aegis-edge doctor" }
        try { $null = & $AEGIS_EDGE redteam --ci 2>$null; Log-Pass "aegis-edge redteam --ci" } catch { Log-Fail "aegis-edge redteam --ci" }
    } else {
        Log-Fail "aegis-edge binary not found at $AEGIS_EDGE"
    }
    Write-Host ""

    # 5. Check baseline docs exist
    Log-Info "Checking baseline docs..."

    $BASELINE_DOC = Join-Path $REPO_ROOT "docs\integrations\current-baseline.md"
    $SAFETY_DOC = Join-Path $REPO_ROOT "docs\integrations\drone-safepoint.md"

    if (Test-Path $BASELINE_DOC) {
        Log-Pass "docs/integrations/current-baseline.md exists"
    } else {
        Log-Fail "docs/integrations/current-baseline.md missing"
    }

    if (Test-Path $SAFETY_DOC) {
        Log-Pass "docs/integrations/drone-safepoint.md exists"
    } else {
        Log-Fail "docs/integrations/drone-safepoint.md missing"
    }
    Write-Host ""

    # Summary
    Log-Info "=== Smoke Test Summary ==="
    if ($ERRORS -eq 0) {
        Write-Host "All checks passed."
        exit 0
    } else {
        Write-Host "$ERRORS check(s) failed."
        exit 1
    }
} finally {
    Pop-Location
}
