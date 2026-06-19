# 01 – Architecture

## The big picture

```
┌─────────────────────────────────────────────────────────────────────┐
│ Docker Desktop Kubernetes (control plane)                             │
│                                                                       │
│  You apply:  XNetwork / XStorage  (a "Composite Resource", XR)        │
│        │                                                              │
│        ▼                                                              │
│  ┌──────────────────────────┐                                        │
│  │ Crossplane core           │  watches XRs, runs the Composition     │
│  │  (apiextensions)          │  pipeline for the matching XRD         │
│  └──────────────┬───────────┘                                        │
│                 │ pipeline step 1                                     │
│                 ▼                                                     │
│  ┌──────────────────────────┐                                        │
│  │ function-go-templating    │  loops over spec arrays, emits one     │
│  │                           │  Managed Resource (MR) per array item  │
│  └──────────────┬───────────┘                                        │
│                 │ pipeline step 2                                     │
│                 ▼                                                     │
│  ┌──────────────────────────┐                                        │
│  │ function-auto-ready       │  marks the XR Ready when all MRs ready │
│  └──────────────┬───────────┘                                        │
│                 ▼                                                     │
│  Managed Resources:  Network, Subnetwork, Router, RouterNAT,          │
│                      Firewall, Bucket, BucketIAMMember ...            │
│        │                                                              │
│  ┌─────▼─────────────────────┐                                       │
│  │ provider-gcp-compute /     │  each MR controller calls the GCP API │
│  │ provider-gcp-storage       │  using creds from the ProviderConfig  │
│  └─────┬─────────────────────┘                                       │
└────────┼──────────────────────────────────────────────────────────-─┘
         │ GCP API (service-account key in `gcp-creds` secret)
         ▼
   Google Cloud project `devopslab-tuzel`  →  real VPCs, subnets, buckets…
```

## The layers, bottom to top

1. **Providers** (`provider-gcp-compute`, `provider-gcp-storage`, shared
   `provider-family-gcp`). These install **Managed Resource (MR)** CRDs — one
   Kubernetes kind per GCP resource type (`Network`, `Subnetwork`, `Bucket`, …).
   Each MR is a 1:1 mirror of a real cloud object; its controller continuously
   reconciles the cloud object to match the MR's `spec.forProvider`.

2. **ProviderConfig** (`gcp.upbound.io/v1beta1`, name `default`). Tells the
   providers *which* GCP project and *which* credentials (a service-account key
   stored in the `gcp-creds` Secret). Cluster-scoped MRs use it automatically.

3. **Composition Functions** (`function-go-templating`, `function-auto-ready`).
   Reusable pipeline steps. go-templating is what turns "an array of 5 subnets"
   into 5 Subnetwork MRs.

4. **The platform API** — your own abstraction:
   - **XRD** (`CompositeResourceDefinition`) defines a new Kubernetes kind
     (`XNetwork`, `XStorage`) and its schema (the arrays, the options).
   - **Composition** says *how* to satisfy that kind — here, "run the
     go-templating function with this template, then auto-ready."

5. **Composite Resources (XRs)** — the things you actually apply
   (`examples/xnetwork.yaml`). One XR fans out to many MRs.

6. **crossview** — a read-only dashboard that lists XRs and MRs.

## Why this shape?

- **Separation of concerns.** Platform authors define *what's allowed* (the XRD
  schema) and *how it's built* (the Composition). Consumers just fill in arrays.
- **Declarative + self-healing.** Delete a bucket in the GCP console and
  Crossplane recreates it — the MR is the source of truth.
- **No cloud IDs in your spec.** Resources reference each other by a logical
  `refName`, resolved at reconcile time via label selectors (see
  [05 – Go Templating](05-go-templating.md)).

## Key decisions (and the why)

| Decision | Why |
|---|---|
| Upjet **provider family** (compute + storage), not the monolith | Smaller CRD surface, faster startup; only install the API groups you use |
| **Cluster-scoped** XRs (`scope: Cluster`) | Networking/storage are shared infra, not per-namespace app config; cluster MRs auto-use the `default` ClusterProviderConfig |
| **Pipeline mode** Composition + go-templating | The only way to loop over arrays; legacy patch-and-transform can't |
| **Label selectors** for `refName` | No hard-coded GCP IDs; references resolve in-cluster and stay declarative |
| Providers pinned to **v2.4.1** | v2.6.0's conversion webhook is unreliable on this cluster — see [07](07-incidents-lessons.md) |
