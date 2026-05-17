$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Resolve-Path (Join-Path $Dir "..\..\..\..")
$Bin = if ($env:EDGE_BIN) { $env:EDGE_BIN } else { Join-Path $Root "zig-out\bin\edge.exe" }
& $Bin health scenario run --policy (Join-Path $Dir "policy.yaml") --scenario (Join-Path $Dir "scenario.yaml")
