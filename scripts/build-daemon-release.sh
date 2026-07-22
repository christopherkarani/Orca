#!/usr/bin/env bash
# Removed: orca-daemon / orca-rs are not product deliverables.
# Shell evaluation is in-process Zig shell_engine (see Agents.md).
echo "build-daemon-release: orca-daemon is no longer built (Zig shell_engine owns Evaluate)." >&2
echo "build-daemon-release: refuse to produce a daemon artifact; use ./scripts/build-release.sh for the CLI product." >&2
exit 1
