# Quickstart

Build and test:

```bash
zig build
zig build test
```

Initialize a policy:

```bash
./zig-out/bin/aegis init --preset generic-agent
./zig-out/bin/aegis policy check .aegis/policy.yaml
./zig-out/bin/aegis doctor
```

Run a command:

```bash
./zig-out/bin/aegis run -- zig build test
```

Run security fixtures:

```bash
./zig-out/bin/aegis redteam --ci
```

Install completions by redirecting the generated script for your shell:

```bash
./zig-out/bin/aegis completions bash
./zig-out/bin/aegis completions zsh
./zig-out/bin/aegis completions fish
./zig-out/bin/aegis completions powershell
```

Aegis reports platform capabilities honestly. On some systems enforcement is wrapper-level or observe-only rather than transparent OS-level sandboxing.
