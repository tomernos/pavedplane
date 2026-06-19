# PavedPlane — Wiki

**PavedPlane** is an open-source, cloud-neutral, best-practices platform for
spinning up infrastructure **environments** with Crossplane. A company applies
*one* declarative resource and gets a complete, opinionated environment — on
whichever cloud they choose.

It works by defining each API **once** (a cloud-neutral XRD) and providing **one
Composition per cloud** (a "configuration module"). GCP is the first module;
Azure is in progress; the structure invites more.

The headline idea: a developer writes *one* small YAML object listing the VPCs,
subnets, NAT gateways, firewall rules, buckets, and IAM bindings they want — as
**arrays** — and Crossplane creates and continuously reconciles all of them in the
target cloud.

## Wiki pages

| Page | What it covers |
|---|---|
| [01 – Architecture](01-architecture.md) | Layers, request flow, the one-API-many-Compositions model |
| [02 – Crossplane Concepts](02-crossplane-concepts.md) | Providers, XRDs, Compositions, Functions, MRs — from scratch |
| [03 – XNetwork](03-xnetwork.md) | The networking API (VPC/subnet/NAT/firewall) — GCP module |
| [04 – XStorage](04-xstorage.md) | The storage API (buckets + bucket IAM) — GCP module |
| [05 – Go Templating Deep Dive](05-go-templating.md) | How the array-loop Composition works |
| [06 – Operations & Troubleshooting](06-operations.md) | Day-2 commands, the webhook gotcha, teardown |
| [07 – Incidents & Lessons Learned](07-incidents-lessons.md) | What broke, why, and the rules that came out of it |

## Repository layout (modular monorepo)

```
.
├── apis/                  # Cloud-NEUTRAL XRDs — the contract every cloud module implements
│   ├── xnetwork/definition.yaml
│   └── xstorage/definition.yaml
├── core/                  # Cloud-agnostic cluster bootstrap (composition functions)
│   └── functions.yaml
├── configuration-gcp/     # The GCP module: providers, Compositions, examples, SA script
│   ├── providers.yaml  providerconfig.yaml  create-sa.sh
│   ├── compositions/  examples/
├── configuration-azure/   # (Eyal) — same XRDs, Azure Compositions   [planned]
├── module-template/       # Scaffold + guide for adding a new cloud module
├── docs/wiki/             # This wiki
├── CONTRIBUTING.md        # How to add a cloud module
└── SUMMARY-FOR-CHATGPT.md # Single-file project explainer for an LLM
```

## How multi-cloud modularity works

```
apis/xnetwork  (ONE cloud-neutral API)  ← consumers write against this
      │
      ├── configuration-gcp   → Composition that builds it on GCP   (this repo's module)
      └── configuration-azure → Composition that builds it on Azure (Eyal's module)
```
A consumer picks the cloud by selecting the Composition (or via a `spec.cloud`
field + composition selector). The long-term umbrella is **`XEnvironment`** — one
object that composes network + storage (+ later compute, IAM, DNS) into a full
landing zone.

## TL;DR of the current (GCP) stack

- **Control plane:** Crossplane v2.3.2 on Docker Desktop K8s (k8s v1.31).
- **GCP module:** Upjet `provider-gcp-compute` + `provider-gcp-storage` (+ family),
  pinned **v2.4.1** (see [lessons](07-incidents-lessons.md)).
- **Composition engine:** `function-go-templating` (loops arrays) + `function-auto-ready`.
- **UI:** `crossview`.
- **Cross-resource references** (`refName`) resolved with **label selectors**, not IDs.
