$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Resolve-Path (Join-Path $Dir "..\..\..\..")
$Bin = if ($env:EDGE_BIN) { $env:EDGE_BIN } else { Join-Path $Root "zig-out\bin\edge.exe" }
& $Bin ardupilot scenario run --policy examples/edge/ardupilot/policies/ardupilot-geofence-basic.yaml --scenario examples/edge/ardupilot/scenarios/waypoint-outside-geofence-deny.yaml
