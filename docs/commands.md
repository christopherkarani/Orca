# Command Guard

Aegis classifies commands that pass through Aegis run paths or generated shims. It is wrapper-mediated, not a guarantee that commands launched outside Aegis are controlled.

High-risk classifications include destructive filesystem commands, privilege escalation, remote shell tools, git remote writes, credential inspection, network scripts piped into shells, command chaining with risky payloads, shell command substitution, and PowerShell encoded commands.

CI mode never prompts. Ask decisions become deny in CI. Command strings written to audit are bounded and redacted before persistence.
