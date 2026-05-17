$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Resolve-Path (Join-Path $Dir "..\..\..\..")
$Bin = if ($env:EDGE_BIN) { $env:EDGE_BIN } else { Join-Path $Root "zig-out\bin\edge.exe" }
& $Bin redteam --fixture approval-expired-denied
