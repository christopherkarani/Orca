# Windows Platform Notes

Windows support is wrapper/shim-oriented for v1.0. Aegis must not claim batch-file forwarding or shell wrappers are a complete security boundary.

Aegis recognizes Windows drive-letter, UNC, PowerShell, `cmd.exe`, and common profile credential path forms in tests and policy helpers. Command classification covers PowerShell encoded-command flags, `Invoke-WebRequest`/`iwr`/`irm` piped to `iex`, destructive shell commands, and common credential reads.

Transparent file and network enforcement are not claimed unless `aegis doctor` reports active support. Generated shims and wrappers must preserve argv as much as the platform path allows and must fail closed in CI for ask decisions.

Tests use synthetic Windows paths only. They must not inspect real Windows profiles or credentials.
