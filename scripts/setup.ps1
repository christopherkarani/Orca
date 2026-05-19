#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
& "$ScriptDir\install.ps1"

$InstallDir = if ($env:ORCA_INSTALL_DIR) { $env:ORCA_INSTALL_DIR } else { Join-Path $env:USERPROFILE ".local\bin" }
& "$InstallDir\orca.exe" setup --auto
