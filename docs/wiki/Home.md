# Crossplane GCP Platform — Wiki

A self-service infrastructure platform built on **Crossplane v2.3**, running on a
local **Docker Desktop Kubernetes** cluster, provisioning **Google Cloud** networking
and storage from a single declarative Kubernetes API.

The headline idea: a developer writes *one* small YAML object listing the VPCs,
subnets, NAT gateways, firewall rules, buckets, and IAM bindings they want — as
**arrays** — and Crossplane creates and continuously reconciles all of them in GCP.

## What you can build with it

```yaml
apiVersion: platform.example.org/v1alpha1
kind: XNetwork           # or XStorage
spec:
  projectID: my-gcp-project
  vpcs:    [ {name: prod}, {name: hub}, ... ]      # many, with options
  subnets: [ {name: ..., vpcRef: prod, ...} ]      # reference a vpc by name
  nats:    [ ... ]
  firewallRules: [ ... ]
```

## Wiki pages

| Page | What it covers |
|---|---|
| [01 – Architecture](01-architecture.md) | The layers, how a request flows from YAML to GCP |
| [02 – Crossplane Concepts](02-crossplane-concepts.md) | Providers, XRDs, Compositions, Functions, Managed Resources — explained from scratch |
| [03 – XNetwork](03-xnetwork.md) | The networking API (VPC/subnet/NAT/firewall) |
| [04 – XStorage](04-xstorage.md) | The storage API (buckets + bucket IAM) |
| [05 – Go Templating Deep Dive](05-go-templating.md) | How the array-loop Composition actually works |
| [06 – Operations & Troubleshooting](06-operations.md) | Day-2 commands, the webhook gotcha, teardown |
| [07 – Incidents & Lessons Learned](07-incidents-lessons.md) | What broke, why, and the rules that came out of it |

## Repository layout

```
.
├── bootstrap/        # Cluster-level install: providers, functions, provider config, SA script
├── apis/
│   ├── xnetwork/     # XRD (definition.yaml) + Composition (composition.yaml)
│   └── xstorage/
├── examples/         # Sample XNetwork / XStorage resources
├── docs/wiki/        # This wiki
└── SUMMARY-FOR-CHATGPT.md   # Single-file project explainer to paste into an LLM
```

## TL;DR of the stack

- **Control plane:** Crossplane v2.3.2 (Helm) on Docker Desktop K8s (k8s v1.31).
- **Cloud provider:** Upbound Upjet GCP provider *family* — `provider-gcp-compute`
  and `provider-gcp-storage` (pinned to **v2.4.1**, see [lessons](07-incidents-lessons.md)).
- **Composition engine:** `function-go-templating` (loops over arrays) +
  `function-auto-ready` (marks the composite ready).
- **UI:** `crossview` (Crossplane dashboard) in the `crossview` namespace.
- **Cross-resource references** (`refName`) are resolved with **label selectors**, not IDs.
