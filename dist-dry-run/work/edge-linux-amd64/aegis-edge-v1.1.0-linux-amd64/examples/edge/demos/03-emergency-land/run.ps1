$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Resolve-Path (Join-Path $Dir "..\..\..\..")
$Bin = if ($env:AEGIS_EDGE) { $env:AEGIS_EDGE } else { Join-Path $Root "zig-out\bin\aegis-edge.exe" }
& $Bin emergency scenario run --policy (Join-Path $Dir "policy.yaml") --scenario (Join-Path $Dir "scenario.yaml")
