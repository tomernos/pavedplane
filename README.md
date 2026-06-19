# PavedPlane

**Paved-road infrastructure environments, on any cloud.**

PavedPlane is an open-source, cloud-neutral platform built on
[Crossplane](https://crossplane.io). It gives teams a *paved road* to
infrastructure: apply one small Kubernetes resource describing the VPCs, subnets,
NAT, firewalls, buckets, and IAM you want — as simple arrays — and PavedPlane
creates and continuously reconciles them in your cloud, following best practices
by default.

It's **modular by design**: each API is defined once as a cloud-neutral contract,
and each cloud ships as a pluggable **configuration module**. GCP is the first
module; Azure is in progress.

```
apis/xnetwork  (one cloud-neutral API)
      ├── configuration-gcp    → builds it on GCP
      └── configuration-azure  → builds it on Azure   (planned)
```

## Why

Wiring cloud infra by hand (or copy-pasting Terraform) is repetitive and
error-prone. PavedPlane turns "I need a standard environment" into one declarative
object, with the opinionated, safe defaults baked into the Composition — and keeps
it reconciled, not just created once.

## Quickstart (GCP module)

```bash
# 1. Crossplane core
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm install crossplane crossplane-stable/crossplane \
  -n crossplane-system --create-namespace --wait

# 2. Shared functions + the GCP module's providers
kubectl apply -f core/functions.yaml
kubectl apply -f configuration-gcp/providers.yaml
kubectl wait --for=condition=Healthy --timeout=5m \
  provider.pkg.crossplane.io --all function.pkg.crossplane.io --all

# 3. GCP credentials (creates SA, grants roles, loads key as a Secret)
bash configuration-gcp/create-sa.sh        # after: gcloud auth login
kubectl apply -f configuration-gcp/providerconfig.yaml

# 4. The platform APIs (cloud-neutral XRDs + GCP Compositions)
kubectl apply -f apis/xnetwork/definition.yaml -f configuration-gcp/compositions/xnetwork.yaml
kubectl apply -f apis/xstorage/definition.yaml -f configuration-gcp/compositions/xstorage.yaml

# 5. Use it
kubectl apply -f configuration-gcp/examples/xnetwork.yaml
kubectl apply -f configuration-gcp/examples/xstorage.yaml
```

## Example

```yaml
apiVersion: platform.example.org/v1alpha1
kind: XNetwork
spec:
  projectID: my-gcp-project
  vpcs:
    - { name: prod, routingMode: REGIONAL }
    - { name: hub,  routingMode: GLOBAL }
  subnets:
    - { name: prod-usc, vpcRef: prod, region: us-central1, ipCidrRange: 10.0.0.0/20 }
  nats:
    - { name: prod-nat, vpcRef: prod, region: us-central1 }
  firewallRules:
    - name: allow-ssh
      vpcRef: prod
      direction: INGRESS
      sourceRanges: ["35.235.240.0/20"]
      allow: [{ protocol: tcp, ports: ["22"] }]
```

## Layout

| Path | Purpose |
|---|---|
| `apis/` | Cloud-neutral XRDs — the contract every cloud module implements |
| `core/` | Cloud-agnostic cluster bootstrap (composition functions) |
| `configuration-gcp/` | The GCP module: providers, Compositions, examples, SA script |
| `module-template/` | Scaffold + guide for adding a new cloud module |
| `docs/wiki/` | Full documentation — start at [`docs/wiki/Home.md`](docs/wiki/Home.md) |
| `CONTRIBUTING.md` | How to add a cloud (your module must satisfy the `apis/` XRDs) |
| `SUMMARY-FOR-CHATGPT.md` | Single-file explainer to paste into an LLM |

## Status

- **GCP module:** working (VPC/subnet/NAT/firewall + buckets/IAM), validated
  end-to-end. Providers pinned to v2.4.1 — read
  [docs/wiki/07-incidents-lessons.md](docs/wiki/07-incidents-lessons.md) before
  upgrading.
- **Azure module:** in progress (separate contributor).
- **`XEnvironment` umbrella API:** planned — one object → a full landing zone.

## Contributing a cloud

See [CONTRIBUTING.md](CONTRIBUTING.md). The short version: implement the existing
`apis/` XRDs with a Composition under `configuration-<cloud>/`, using
`module-template/` as a starting point. Your module is interchangeable with
others because they all satisfy the same API.

## License

TBD (intended: Apache-2.0).
