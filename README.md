# TrustyAI Guardrails Operator

## Overview

The TrustyAI Guardrails Operator provides a unified platform for deploying and managing various AI guardrail servers. It imports and orchestrates multiple guardrails controllers, making it easy to deploy guardrails solutions in your cluster.

> ### 💡 Check out the [quickstart guide](docs/nemo_guardrails_quickstart.md)! 💡

## Supported Guardrails

Currently, the operator supports:

- **NeMo Guardrails**: NVIDIA's framework for adding programmable guardrails to LLM-based conversational systems


## Features

- **Modular Architecture**: Each guardrails technology is implemented as an importable controller
- **Unified Management**: Single operator to manage multiple guardrails types
- **OpenShift Integration**: Native support for OpenShift Routes and security features
- **Flexible Configuration**: ConfigMap-based configuration for easy customization
- **Event Recording**: Kubernetes events for all major operations

## Architecture

```
trustyai-guardrails-operator/
├── cmd/main.go                      # Operator entrypoint
├── config/
│   └── manager/                     # Deployment manifests
└── go.mod                           # Dependencies

Imported Controllers:
├── nemo-guardrails-controller       # NeMo Guardrails CRD & controller
└── trustyai-operator-common         # Shared utilities
```

## Installation

### Prerequisites

- Kubernetes 1.29+ or OpenShift 4.12+
- kubectl or oc CLI tool
- Go 1.23+ (for building from source)

### Install CRDs

```bash
make install
```

This will install the CRDs for all supported guardrails types.

### Deploy the Operator

```bash
make deploy
```

Or run locally for development:

```bash
make run
```

## Quickstarts
For tutorials to get you started quickly, check out:
* [NeMo Guardrails Quickstart](docs/nemo_guardrails_quickstart.md): Perform PII, code injection, and toxic language guardrailing.

## Usage

### Creating a NeMo Guardrails Instance

First, create a ConfigMap with your NeMo Guardrails configuration:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-nemo-config
  namespace: default
data:
  config.yaml: |
    models:
      - type: main
        engine: openai
        model: gpt-3.5-turbo
    rails:
      input:
        flows:
          - self check input
  actions.py: |
    # Your custom actions here
    pass
```

Then create a NemoGuardrails resource:

```yaml
apiVersion: trustyai.opendatahub.io/v1alpha1
kind: NemoGuardrails
metadata:
  name: my-guardrails
  namespace: default
spec:
  nemoConfigs:
    - name: default-config
      configMaps:
        - my-nemo-config
      default: true
  env:
    - name: LOG_LEVEL
      value: "INFO"
```

Apply the resource:

```bash
kubectl apply -f my-nemoguardrails.yaml
```

### Checking Status

```bash
kubectl get nemoguardrails
kubectl describe nemoguardrails my-guardrails
```

### Accessing the Service

The operator creates a Service for your guardrails instance. On OpenShift, it also creates a Route:

```bash
# Get the service
kubectl get svc my-guardrails

# On OpenShift, get the route
oc get route my-guardrails
```

## Configuration

### Operator ConfigMap

The operator uses a ConfigMap for configuration. Create one in the operator's namespace:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: trustyai-guardrails-operator-config
  namespace: trustyai-guardrails-operator-system
data:
  nemo-guardrails-image: "quay.io/trustyai/nemo-guardrails:latest"
  kube-rbac-proxy: "gcr.io/kubebuilder/kube-rbac-proxy:v0.8.0"
```

Specify the ConfigMap name when starting the operator:

```bash
./bin/manager --configmap=trustyai-guardrails-operator-config
```

### Command-Line Flags

- `--metrics-bind-address`: The address the metric endpoint binds to (default: `:8080`)
- `--health-probe-bind-address`: The address the probe endpoint binds to (default: `:8081`)
- `--leader-elect`: Enable leader election for controller manager
- `--configmap`: Name of the ConfigMap containing operator configuration (default: `trustyai-service-operator-config`)
- `--namespace`: Namespace where the operator is running (auto-detected if not specified)

### Environment Variables

- `WATCH_NAMESPACES`: Comma-separated list of namespaces to watch. If empty or unset, watches all namespaces (cluster-wide). Example: `"namespace1,namespace2,namespace3"`

**Important**: When deploying alongside the TrustyAI Service Operator, configure namespace watching to avoid CR ownership conflicts. See [Multi-Operator Deployment Guide](docs/multi-operator-deployment.md).

## Development

### Building

```bash
make build
```

### Running Tests

```bash
make test
```

### Running Locally

```bash
make run
```

### Building Docker Image

```bash
make docker-build IMG=myregistry/trustyai-guardrails-operator:latest
make docker-push IMG=myregistry/trustyai-guardrails-operator:latest
```

## Architecture Details

### Modular Controller Design

The Guardrails Operator follows a modular architecture where each guardrails technology is:

1. **Implemented as a standalone controller module** with its own API types and reconciliation logic
2. **Imported via Go modules** using the setup package pattern
3. **Registered with the operator's manager** at startup
4. **Independently versioned and tested**

This design allows:
- Easy addition of new guardrails types
- Independent development and testing of each controller
- Reuse of controllers across multiple operators
- Clear separation of concerns

### Adding New Guardrails Controllers

To add a new guardrails controller:

1. **Create the controller module** following the pattern of `nemo-guardrails-controller`
2. **Add a setup package** (`pkg/setup/setup.go`) with:
   - `ControllerName` constant
   - `SetupWithManager` function
   - `RegisterScheme` function
3. **Update the operator's `go.mod`** to import the new controller
4. **Register in `cmd/main.go`**:
   ```go
   import newcontroller "github.com/org/new-controller/pkg/setup"

   func init() {
       utilruntime.Must(newcontroller.RegisterScheme(scheme))
   }

   func main() {
       // ... existing code ...
       if err = newcontroller.SetupWithManager(mgr, operatorNamespace, configMapName, recorder); err != nil {
           setupLog.Error(err, "unable to create controller", "controller", newcontroller.ControllerName)
           os.Exit(1)
       }
   }
   ```
5. **Update the Makefile** to install the new CRDs

## Troubleshooting

### Operator Not Starting

Check the operator logs:

```bash
kubectl logs -n trustyai-guardrails-operator-system deployment/trustyai-guardrails-operator
```

Common issues:
- Missing ConfigMap
- Invalid namespace
- CRDs not installed

### Guardrails Instance Not Starting

Check the status:

```bash
kubectl describe nemoguardrails <name>
```

Check events:

```bash
kubectl get events --sort-by='.lastTimestamp'
```

Common issues:
- Missing configuration ConfigMaps
- Invalid NeMo configuration syntax
- Missing container images

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

Apache License 2.0

## Related Projects

- [nemo-guardrails-controller](https://github.com/trustyai-explainability/nemo-guardrails-controller) - NeMo Guardrails controller module
- [trustyai-operator-common](https://github.com/trustyai-explainability/trustyai-operator-common) - Shared utilities for TrustyAI operators
- [NeMo Guardrails](https://github.com/NVIDIA/NeMo-Guardrails) - NVIDIA's guardrails framework

## Support

For issues and questions:
- File an issue on GitHub
- Review existing issues and discussions
