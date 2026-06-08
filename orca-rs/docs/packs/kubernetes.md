# Kubernetes Packs

This document describes packs in the `kubernetes` category.

## Packs in this Category

- [kubectl](#kuberneteskubectl)
- [Helm](#kuberneteshelm)
- [Kustomize](#kuberneteskustomize)

---

## kubectl

**Pack ID:** `kubernetes.kubectl`

Protects against destructive kubectl operations like delete namespace, drain, and mass deletion

### Keywords

Commands containing these keywords are checked against this pack:

- `kubectl`
- `delete`
- `drain`
- `cordon`
- `taint`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `kubectl-get` | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+get(?=\s\|$)` |
| `kubectl-describe` | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+describe(?=\s\|$)` |
| `kubectl-logs` | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+logs(?=\s\|$)` |
| `kubectl-dry-run` | `kubectl\b.*--dry-run(?:=(?:client\|server))?(?:\s\|$)` |
| `kubectl-diff` | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+diff(?=\s\|$)` |
| `kubectl-explain` | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+explain(?=\s\|$)` |
| `kubectl-top` | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+top(?=\s\|$)` |
| `kubectl-config` | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+config(?=\s\|$)` |
| `kubectl-api` | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+api-(?:resources\|versions)(?=\s\|$)` |
| `kubectl-version` | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+version(?=\s\|$)` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `delete-namespace` | kubectl delete namespace removes the entire namespace and ALL resources within it. | critical |
| `delete-all` | kubectl delete --all removes ALL resources of that type. Use --dry-run=client first. | high |
| `delete-all-namespaces` | kubectl delete with -A/--all-namespaces affects ALL namespaces. Very dangerous! | critical |
| `drain-node` | kubectl drain evicts all pods from a node. Ensure proper pod disruption budgets. | high |
| `cordon-node` | kubectl cordon marks a node unschedulable. Existing pods continue running. | medium |
| `taint-noexecute` | kubectl taint with NoExecute evicts existing pods that don't tolerate the taint. | high |
| `delete-workload` | kubectl delete deployment/statefulset/daemonset removes the workload. Use --dry-run first. | high |
| `delete-pvc` | kubectl delete pvc may permanently delete data if ReclaimPolicy is Delete. | critical |
| `delete-pv` | kubectl delete pv may permanently delete the underlying storage. | critical |
| `scale-to-zero` | kubectl scale --replicas=0 stops all pods for the workload. | high |
| `delete-force` | kubectl delete --force --grace-period=0 immediately removes resources without graceful shutdown. | critical |
| `apply-force` | kubectl apply --force deletes and recreates resources, causing downtime. | high |
| `delete-from-directory` | kubectl delete -f with directories or --recursive deletes many resources at once. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "kubernetes.kubectl:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "kubernetes.kubectl:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Helm

**Pack ID:** `kubernetes.helm`

Protects against destructive Helm operations like uninstall and rollback without dry-run

### Keywords

Commands containing these keywords are checked against this pack:

- `helm`
- `uninstall`
- `delete`
- `rollback`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `helm-list` | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+list(?=\s\|$)` |
| `helm-status` | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+status(?=\s\|$)` |
| `helm-history` | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+history(?=\s\|$)` |
| `helm-show` | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+show(?=\s\|$)` |
| `helm-inspect` | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+inspect(?=\s\|$)` |
| `helm-get` | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+get(?=\s\|$)` |
| `helm-search` | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+search(?=\s\|$)` |
| `helm-repo` | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+repo(?=\s\|$)` |
| `helm-dry-run` | `helm\b.*--dry-run(?:=(?:true\|client\|server))?(?:\s\|$)` |
| `helm-template` | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+template(?=\s\|$)` |
| `helm-lint` | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+lint(?=\s\|$)` |
| `helm-diff` | `helm\b(?:\s+--?\S+(?:\s+\S+)?)*\s+diff(?=\s\|$)` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `uninstall` | helm uninstall removes the release and all its resources. Use --dry-run first. | critical |
| `rollback` | helm rollback reverts to a previous release. Use --dry-run to preview changes. | high |
| `upgrade-force` | helm upgrade --force deletes and recreates resources, causing downtime. | high |
| `upgrade-reset-values` | helm upgrade --reset-values discards all previously set values. | high |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "kubernetes.helm:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "kubernetes.helm:*"
reason = "Your reason here"
risk_acknowledged = true
```

---

## Kustomize

**Pack ID:** `kubernetes.kustomize`

Protects against destructive Kustomize operations when combined with kubectl delete or applied without review

### Keywords

Commands containing these keywords are checked against this pack:

- `kustomize`
- `kubectl`

### Safe Patterns (Allowed)

These patterns match safe commands that are always allowed:

| Pattern Name | Pattern |
|--------------|----------|
| `kustomize-build` | `kustomize\b(?:\s+--?\S+(?:\s+\S+)?)*\s+build\b(?!.*\\|)` |
| `kubectl-kustomize` | `kubectl\b(?:\s+--?\S+(?:\s+\S+)?)*\s+kustomize\b(?!.*\\|)` |
| `kustomize-diff` | `kustomize\b.*?\bbuild\s+.*\\|\s*kubectl\b.*?\s+diff\b` |
| `kustomize-dry-run` | `kustomize\b.*?\bbuild\s+.*\\|\s*kubectl\b.*--dry-run(?:=(?:client\|server))?(?:\s\|$)` |

### Destructive Patterns (Blocked)

These patterns match potentially destructive commands:

| Pattern Name | Reason | Severity |
|--------------|--------|----------|
| `kustomize-delete` | kustomize build \| kubectl delete removes all resources in the kustomization. | critical |
| `kubectl-kustomize-delete` | kubectl kustomize \| kubectl delete removes all resources in the kustomization. | critical |
| `kubectl-delete-k` | kubectl delete -k removes all resources defined in the kustomization. Use --dry-run first. | critical |

### Allowlist Guidance

To allowlist a specific rule from this pack, add to your allowlist:

```toml
[[allow]]
rule = "kubernetes.kustomize:<pattern-name>"
reason = "Your reason here"
```

To allowlist all rules from this pack (use with caution):

```toml
[[allow]]
rule = "kubernetes.kustomize:*"
reason = "Your reason here"
risk_acknowledged = true
```

---
