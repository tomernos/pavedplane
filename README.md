# Crossplane GCP Networking Platform

Crossplane **v2.3** on Docker Desktop Kubernetes, with the **GCP** provider, a
**go-templating** Composition that generates many VPCs / subnets / Cloud NAT /
firewall rules from a single declarative API, and **crossview** for visualization.

## What's installed

| Component | Version | Notes |
|---|---|---|
| Crossplane core | v2.3.2 | Helm release `crossplane` in `crossplane-system` |
| Crossplane CLI | v2.3.2 | `~/.local/bin/crossplane` |
| provider-gcp-compute | v2.4.1 | Pulls in `provider-family-gcp` automatically |
| function-go-templating | v0.11.4 | Loops over the spec arrays to render resources |
| function-auto-ready | v0.6.4 | Marks the XR Ready when composed resources are Ready |
| crossview | latest | Crossplane UI dashboard (namespace `crossview`) |

## Layout

```
.
├── bootstrap/
│   ├── 01-providers.yaml       # GCP compute provider
│   ├── 02-functions.yaml       # go-templating + auto-ready functions
│   └── 03-providerconfig.yaml  # ClusterProviderConfig (needs GCP creds)
├── apis/
│   └── xnetwork/
│       ├── definition.yaml     # XRD (apiextensions.crossplane.io/v2)
│       └── composition.yaml    # Pipeline Composition w/ go-templating
├── examples/
│   └── xnetwork.yaml           # Sample XR: 3 VPCs, subnets, NAT, firewalls
└── crossview/                  # UI install notes
```

## The XNetwork API

One `XNetwork` resource describes **arrays** of networking resources. Resources
reference a VPC by a logical `vpcRef` that matches a `vpcs[].name` (the
**refName** pattern). The Composition wires them together with label selectors —
no hard-coded GCP IDs.

```yaml
spec:
  projectID: my-gcp-project
  vpcs:           [{ name, autoCreateSubnetworks, routingMode }]
  subnets:        [{ name, vpcRef, region, ipCidrRange, privateIpGoogleAccess }]
  nats:           [{ name, vpcRef, region, natIpAllocateOption, sourceSubnetworkIpRangesToNat }]
  firewallRules:  [{ name, vpcRef, direction, priority, sourceRanges, destinationRanges, allow:[{protocol, ports}] }]
```

Each array entry becomes one (or, for NAT, two) GCP managed resources:

| Spec array | Generated managed resource(s) | refName field |
|---|---|---|
| `vpcs[]` | `Network` | `name` (the target of vpcRef) |
| `subnets[]` | `Subnetwork` | `vpcRef` → a vpc name |
| `nats[]` | `Router` + `RouterNAT` | `vpcRef` → a vpc name |
| `firewallRules[]` | `Firewall` | `vpcRef` → a vpc name |

## Install order (from scratch)

```bash
# 1. Core (already installed via Helm)
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm install crossplane crossplane-stable/crossplane \
  -n crossplane-system --create-namespace --wait

# 2. Provider + functions
kubectl apply -f bootstrap/01-providers.yaml
kubectl apply -f bootstrap/02-functions.yaml
kubectl wait --for=condition=Healthy --timeout=5m \
  provider.pkg.crossplane.io/provider-gcp-compute \
  function.pkg.crossplane.io/function-go-templating \
  function.pkg.crossplane.io/function-auto-ready

# 3. GCP credentials (see header of bootstrap/03-providerconfig.yaml)
#    Create the gcp-creds Secret, set projectID, then:
kubectl apply -f bootstrap/03-providerconfig.yaml

# 4. The XNetwork API
kubectl apply -f apis/xnetwork/definition.yaml
kubectl apply -f apis/xnetwork/composition.yaml

# 5. Use it
kubectl apply -f examples/xnetwork.yaml
```

> Image pulls into the Docker Desktop k8s VM occasionally fail with
> `unexpected EOF`. It's transient — `kubectl delete pod <stuck-pod> -n <ns>`
> resets the backoff and the re-pull usually succeeds.

## Inspecting a deployment

```bash
kubectl get xnetwork demo
kubectl describe xnetwork demo
# All managed resources for one XNetwork (scoped by the xr label):
kubectl get network,subnetwork,router,routernat,firewall \
  -l platform.example.org/xr=demo

# Dry-run the composition locally (no cluster apply) with the CLI:
crossplane render examples/xnetwork.yaml apis/xnetwork/composition.yaml bootstrap/02-functions.yaml
```

## crossview UI

See `crossview/` for the Helm install and the `kubectl port-forward` command to
reach the dashboard.
