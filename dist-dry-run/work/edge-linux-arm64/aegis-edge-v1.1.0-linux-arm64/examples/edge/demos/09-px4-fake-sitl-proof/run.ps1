$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Resolve-Path (Join-Path $Dir "..\..\..\..")
$Bin = if ($env:AEGIS_EDGE) { $env:AEGIS_EDGE } else { Join-Path $Root "zig-out\bin\aegis-edge.exe" }
& $Bin px4 scenario run --policy examples/edge/px4/policies/px4-geofence-basic.yaml --scenario examples/edge/px4/scenarios/waypoint-outside-geofence-deny.yaml
