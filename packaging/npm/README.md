# Orca npm Template

This package is the npm launcher template for the Zig-built `orca` CLI binary.

Release automation renders the publishable npm package under `dist/package-manifests/npm/` with release checksums from `dist/checksums.txt`. Until then, `postinstall` fails closed instead of pretending a binary was installed; use the source build or platform install scripts with `dist/checksums.txt` verification.
