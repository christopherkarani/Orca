# Infrastructure as Code Packs

This document describes packs in the `infrastructure` category.

## Packs in this Category

- [Terraform](#infrastructureterraform)
- [Ansible](#infrastructureansible)
- [Pulumi](#infrastructurepulumi)

---

## Terraform

**Pack ID:** `infrastructure.terraform`

Protects against destructive Terraform operations like destroy, taint, and apply with -auto-approve

### Keywords

Commands containing these keywords are checked against this pack:

- `terraform`
- `destroy`
- `taint`
- `state`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `terraform-plan` | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+plan(?=\s\|$)(?!\s+.*-destroy)` |
| `terraform-init` | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+init(?=\s\|$)` |
| `terraform-validate` | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+validate(?=\s\|$)` |
| `terraform-fmt` | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+fmt(?=\s\|$)` |
| `terraform-show` | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+show(?=\s\|$)` |
| `terraform-output` | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+output(?=\s\|$)` |
| `terraform-state-list` | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+state\s+list(?=\s\|$)` |
| `terraform-state-show` | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+state\s+show(?=\s\|$)` |
| `terraform-graph` | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+graph(?=\s\|$)` |
| `terraform-version` | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+version(?=\s\|$)` |
| `terraform-providers` | `terraform\b(?:\s+--?\S+(?:\s+\S+)?)*\s+providers(?=\s\|$)` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `plan-destroy` | terraform plan -destroy shows what would be destroyed. Review carefully before applying. | medium |
| `destroy` | terraform destroy removes ALL managed infrastructure. Use 'terraform plan -destroy' first. | critical |
| `apply-auto-approve` | terraform apply -auto-approve skips confirmation. Remove -auto-approve for safety. | high |
| `taint` | terraform taint marks a resource to be destroyed and recreated on next apply. | high |
| `state-rm` | terraform state rm removes resource from state without destroying it. Resource becomes unmanaged. | high |
| `state-mv` | terraform state mv moves resources in state. Incorrect moves can cause resource recreation. | high |
| `force-unlock` | terraform force-unlock removes state lock. Only use if lock is stale. | high |
| `workspace-delete` | terraform workspace delete removes a workspace. Ensure it's not in use. | medium |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "infrastructure.terraform:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "infrastructure.terraform:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Ansible

**Pack ID:** `infrastructure.ansible`

Protects against destructive Ansible operations like dangerous shell commands and unchecked playbook runs

### Keywords

Commands containing these keywords are checked against this pack:

- `ansible`
- `playbook`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `ansible-check` | `ansible(?:-playbook)?\b[^\n;&\|]*--check(?:\s\|$)[^\n;&\|]*$` |
| `ansible-list-hosts` | `ansible(?:-playbook)?\b[^\n;&\|]*--list-hosts(?:\s\|$)[^\n;&\|]*$` |
| `ansible-list-tasks` | `ansible(?:-playbook)?\b[^\n;&\|]*--list-tasks(?:\s\|$)[^\n;&\|]*$` |
| `ansible-syntax` | `ansible(?:-playbook)?\b[^\n;&\|]*--syntax-check(?:\s\|$)[^\n;&\|]*$` |
| `ansible-inventory` | `ansible-inventory\b[^\n;&\|]*$` |
| `ansible-doc` | `ansible-doc\b[^\n;&\|]*$` |
| `ansible-config` | `ansible-config\b[^\n;&\|]*$` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `shell-rm-rf` | Ansible shell/command with 'rm -rf' is destructive. Review carefully. | critical |
| `shell-reboot` | Ansible shell/command with reboot/shutdown affects system availability. | high |
| `playbook-all-hosts` | ansible-playbook without --check or --limit may affect all hosts. Use --check first. | high |
| `extra-vars-delete` | Ansible extra-vars contains potentially destructive keywords. Review carefully. | medium |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "infrastructure.ansible:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "infrastructure.ansible:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Pulumi

**Pack ID:** `infrastructure.pulumi`

Protects against destructive Pulumi operations like destroy and up with -y (auto-approve)

### Keywords

Commands containing these keywords are checked against this pack:

- `pulumi`
- `destroy`
- `state`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `pulumi-preview` | `pulumi\b(?:\s+--?\S+(?:\s+\S+)?)*\s+preview(?=\s\|$)` |
| `pulumi-stack-ls` | `pulumi\b(?:\s+--?\S+(?:\s+\S+)?)*\s+stack\s+ls(?=\s\|$)` |
| `pulumi-stack-select` | `pulumi\b(?:\s+--?\S+(?:\s+\S+)?)*\s+stack\s+select(?=\s\|$)` |
| `pulumi-stack-init` | `pulumi\b(?:\s+--?\S+(?:\s+\S+)?)*\s+stack\s+init(?=\s\|$)` |
| `pulumi-config` | `pulumi\b(?:\s+--?\S+(?:\s+\S+)?)*\s+config(?=\s\|$)` |
| `pulumi-whoami` | `pulumi\b(?:\s+--?\S+(?:\s+\S+)?)*\s+whoami(?=\s\|$)` |
| `pulumi-version` | `pulumi\b(?:\s+--?\S+(?:\s+\S+)?)*\s+version(?=\s\|$)` |
| `pulumi-about` | `pulumi\b(?:\s+--?\S+(?:\s+\S+)?)*\s+about(?=\s\|$)` |
| `pulumi-logs` | `pulumi\b(?:\s+--?\S+(?:\s+\S+)?)*\s+logs(?=\s\|$)` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `destroy` | pulumi destroy removes ALL managed infrastructure. Use 'pulumi preview --diff' first. | critical |
| `up-yes` | pulumi up -y skips confirmation. Remove -y flag for safety. | high |
| `state-delete` | pulumi state delete removes resource from state without destroying it. | high |
| `stack-rm` | pulumi stack rm removes the stack. Use --force only if stack is empty. | high |
| `refresh-yes` | pulumi refresh -y auto-approves state changes. Review changes first. | medium |
| `cancel` | pulumi cancel terminates an in-progress update, which may leave resources in inconsistent state. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "infrastructure.pulumi:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "infrastructure.pulumi:*"
reason = "Your reason here"
risk_acknowledged = true
```

---
