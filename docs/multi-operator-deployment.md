# Multi-Operator Deployment Guide

This guide explains how to deploy the TrustyAI Guardrails Operator alongside the TrustyAI Service Operator in the same Kubernetes cluster without CR ownership conflicts.

## The Problem

Both operators can manage `NemoGuardrails` custom resources:
- **trustyai-guardrails-operator**: Dedicated operator for guardrails controllers
- **trustyai-service-operator**: Multi-service operator that includes guardrails support

When both are deployed cluster-wide, they will both try to reconcile the same `NemoGuardrails` CRs, causing conflicts.

## Solution: Namespace-Based Separation

The TrustyAI Guardrails Operator supports namespace-scoped watching via the `WATCH_NAMESPACES` environment variable.

### Deployment Scenarios

#### Scenario 1: Single Operator (Default)
Deploy only one operator. No configuration needed.

**Option A: Guardrails Operator Only**
```bash
kubectl apply -f trustyai-guardrails-operator.yaml
```

**Option B: Service Operator Only**
```bash
kubectl apply -f trustyai-service-operator.yaml
```

---

#### Scenario 2: Both Operators with Namespace Separation

**Use Case**: You want dedicated guardrails management in specific namespaces, while the service operator handles other services.

**Configuration**:
1. Deploy trustyai-guardrails-operator to watch only specific namespaces
2. Deploy trustyai-service-operator cluster-wide (default)

**Example Setup**:

```yaml
# trustyai-guardrails-operator watches only guardrails-* namespaces
apiVersion: apps/v1
kind: Deployment
metadata:
  name: trustyai-guardrails-operator-controller-manager
  namespace: trustyai-guardrails-operator-system
spec:
  template:
    spec:
      containers:
      - name: manager
        env:
        - name: WATCH_NAMESPACES
          value: "guardrails-prod,guardrails-dev"
```

```yaml
# trustyai-service-operator watches all namespaces (default)
# Deploy as-is, no changes needed
```

**Result**:
- `NemoGuardrails` CRs in `guardrails-prod` and `guardrails-dev` → managed by guardrails operator
- `NemoGuardrails` CRs in other namespaces → managed by service operator
- No conflicts

---

#### Scenario 3: Guardrails Operator in Its Own Namespace Only

**Use Case**: Test or demo environment where guardrails operator manages only CRs in its deployment namespace.

**Configuration**:

Using Kubernetes Downward API:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: trustyai-guardrails-operator-controller-manager
  namespace: trustyai-guardrails-operator-system
spec:
  template:
    spec:
      containers:
      - name: manager
        env:
        - name: WATCH_NAMESPACES
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
```

**Result**:
- Guardrails operator only manages CRs in `trustyai-guardrails-operator-system`
- Service operator manages CRs everywhere else

---

## Configuration Methods

### Method 1: Direct YAML Edit

Edit the deployment manifest before applying:
```yaml
env:
- name: WATCH_NAMESPACES
  value: "namespace1,namespace2,namespace3"
```

### Method 2: Kustomize Patch

Create a patch file:
```yaml
# patch-watch-namespaces.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: trustyai-guardrails-operator-controller-manager
  namespace: trustyai-guardrails-operator-system
spec:
  template:
    spec:
      containers:
      - name: manager
        env:
        - name: WATCH_NAMESPACES
          value: "guardrails-prod,guardrails-dev"
```

Apply with kustomize:
```yaml
# kustomization.yaml
resources:
- trustyai-guardrails-operator.yaml

patches:
- path: patch-watch-namespaces.yaml
```

### Method 3: kubectl set env

After deployment, update the environment variable:
```bash
kubectl set env deployment/trustyai-guardrails-operator-controller-manager \
  -n trustyai-guardrails-operator-system \
  WATCH_NAMESPACES="guardrails-prod,guardrails-dev"
```

### Method 4: ConfigMap (Advanced)

Create a ConfigMap:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: operator-config
  namespace: trustyai-guardrails-operator-system
data:
  watch-namespaces: "guardrails-prod,guardrails-dev"
```

Reference in deployment:
```yaml
env:
- name: WATCH_NAMESPACES
  valueFrom:
    configMapKeyRef:
      name: operator-config
      key: watch-namespaces
```

---

## RBAC Considerations

### Cluster-Wide Watching (Default)
Requires ClusterRole and ClusterRoleBinding to access resources across all namespaces.

**Included in default deployment manifests.**

### Namespace-Scoped Watching
When watching specific namespaces, you can optionally reduce RBAC permissions to only those namespaces.

**Example**: Role instead of ClusterRole
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: trustyai-guardrails-operator-manager-role
  namespace: guardrails-prod
rules:
- apiGroups:
  - trustyai.opendatahub.io
  resources:
  - nemoguardrails
  verbs:
  - create
  - delete
  - get
  - list
  - patch
  - update
  - watch
# ... additional rules
```

---

## Verification

### Check Which Namespaces Are Being Watched

```bash
# View operator logs
kubectl logs -n trustyai-guardrails-operator-system \
  deployment/trustyai-guardrails-operator-controller-manager

# Look for log lines:
# "Configuring operator to watch specific namespaces" namespaces="ns1,ns2"
# OR
# "Watching all namespaces (cluster-wide)"
```

### Test Separation

1. Create a `NemoGuardrails` CR in a watched namespace:
```bash
kubectl apply -f - <<EOF
apiVersion: trustyai.opendatahub.io/v1alpha1
kind: NemoGuardrails
metadata:
  name: test-guardrails
  namespace: guardrails-prod
spec:
  configs: []
EOF
```

2. Check which operator reconciled it:
```bash
# Check events
kubectl describe nemoguardrails test-guardrails -n guardrails-prod

# Check operator logs
kubectl logs -n trustyai-guardrails-operator-system \
  deployment/trustyai-guardrails-operator-controller-manager | grep test-guardrails
```

---

## Troubleshooting

### Both operators reconciling the same CR

**Symptoms**: Resources being created/updated repeatedly, conflicting status updates

**Solution**: Ensure namespace separation is configured correctly
1. Check `WATCH_NAMESPACES` env var in guardrails operator
2. Verify no overlap between watched namespaces
3. Check RBAC permissions

### Operator not reconciling CRs

**Symptoms**: CRs created but no Deployments/Services appear

**Possible Causes**:
1. CR is in a namespace not being watched
2. RBAC permissions insufficient
3. Operator not running

**Debug**:
```bash
# Check operator is running
kubectl get pods -n trustyai-guardrails-operator-system

# Check namespace configuration
kubectl get deployment trustyai-guardrails-operator-controller-manager \
  -n trustyai-guardrails-operator-system -o yaml | grep -A 5 "WATCH_NAMESPACES"

# Check logs for errors
kubectl logs -n trustyai-guardrails-operator-system \
  deployment/trustyai-guardrails-operator-controller-manager --tail=100
```

---

## Recommendations

### Development/Testing
- Use separate namespaces for each operator's test CRs
- Set guardrails operator to watch only its test namespace
- Easier to debug and isolate issues

### Production
- **Option 1 (Recommended)**: Deploy only the operator you need
  - If you only use guardrails → deploy guardrails operator only
  - If you use multiple TrustyAI services → deploy service operator only

- **Option 2**: Clear namespace separation
  - Guardrails operator watches `*-guardrails` namespaces
  - Service operator disabled for guardrails or watches other namespaces
  - Document the separation clearly for operations team

### Multi-Tenant Environments
- Deploy one guardrails operator per tenant namespace
- Use RBAC to isolate tenants
- Each operator watches only its tenant's namespace:
  ```yaml
  env:
  - name: WATCH_NAMESPACES
    valueFrom:
      fieldRef:
        fieldPath: metadata.namespace
  ```

---

## Summary

| Deployment Scenario | Guardrails Operator WATCH_NAMESPACES | Service Operator | Result |
|---------------------|--------------------------------------|------------------|--------|
| Single operator (guardrails only) | `""` (cluster-wide) | Not deployed | Guardrails operator manages all CRs |
| Single operator (service only) | Not deployed | Cluster-wide | Service operator manages all CRs |
| Both with separation | `"ns1,ns2"` | Cluster-wide | Guardrails in ns1,ns2; Service elsewhere |
| Both with self-namespace | `metadata.namespace` | Cluster-wide | Guardrails in its own namespace only |

The key to avoiding conflicts is ensuring no two operators watch the same namespace for `NemoGuardrails` resources.
