# 02 – Crossplane Concepts (from scratch)

If you've never used Crossplane, read this first. It explains every term used
elsewhere in the wiki.

## What Crossplane is

Crossplane turns Kubernetes into a **control plane for cloud infrastructure**.
Instead of `kubectl` only managing Pods and Services, you teach it about
`Networks`, `Buckets`, etc., and it creates them in AWS/GCP/Azure and keeps them
in sync — the same reconcile loop Kubernetes uses for its own objects.

You interact with it entirely through the Kubernetes API (`kubectl apply`).

## The core objects

### Provider
A package you install (like an app) that teaches Crossplane about one cloud's
resources. Installing `provider-gcp-compute` registers CRDs such as
`Network.compute.gcp.upbound.io`. A provider runs a **controller pod** per
resource type that talks to the cloud API.

> **Provider family:** Upbound split the giant GCP provider into per-service
> packages (`-compute`, `-storage`, …) that share a `provider-family-gcp`
> package holding the common `ProviderConfig`. All family members must run the
> **same version**.

### Managed Resource (MR)
A 1:1 representation of a single cloud object, e.g. a `Bucket`. Its
`spec.forProvider` holds the cloud fields; its `status` reflects reality. The
provider reconciles the cloud object to match. MRs are the "primitives."

```yaml
apiVersion: storage.gcp.upbound.io/v1beta1
kind: Bucket
spec:
  forProvider:
    location: US
    storageClass: STANDARD
```

### ProviderConfig
Holds the credentials + project the provider uses. Here it's named `default`,
points at project `devopslab-tuzel`, and reads a service-account key from the
`gcp-creds` Secret. Cluster-scoped MRs use `default` automatically.

### CompositeResourceDefinition (XRD)
Defines a **new, higher-level API** — your own kind like `XNetwork`. It declares:
- the API group/kind/version,
- the **schema** (the `spec` fields your users fill in),
- the **scope** (`Cluster` or `Namespaced`).

Think of an XRD as "the CRD for your abstraction."

### Composition
The recipe that says *how* to satisfy an XR. In **Pipeline mode** it's a list of
**function** steps. Our Compositions have two steps:
1. `function-go-templating` — render the MRs from the spec arrays.
2. `function-auto-ready` — set the XR `Ready` once all MRs are `Ready`.

### Composite Resource (XR)
An instance of your XRD — the thing you `kubectl apply`. One `XNetwork` named
`demo` produces many MRs (Networks, Subnets, …). The XR **owns** those MRs, so
deleting the XR cascades to them.

### Composition Function
A small program (shipped as an OCI image, run by Crossplane) that takes the
observed state and returns desired resources. `function-go-templating` lets you
write Go templates (with Sprig helpers) that emit YAML — perfect for looping.

## How a reconcile flows

```
apply XR ──► Crossplane selects the Composition for that XRD
         ──► runs the pipeline: go-templating emits desired MRs
         ──► Crossplane creates/updates those MRs (sets ownerRef to the XR)
         ──► each provider reconciles its MR → calls GCP
         ──► function-auto-ready flips XR.Ready=True when all MRs are Ready
```

## Status fields you'll watch

- **SYNCED** — Crossplane successfully reconciled the object's spec (for an MR:
  the provider talked to GCP without error).
- **READY** — the underlying cloud resource exists and is healthy.
- A resource can be `SYNCED=True, READY=False` while the cloud object is still
  being created.

## Useful mental model

> **MRs are like Terraform resources; the Composition is like a Terraform module;
> the XR is like a `module "x" { … }` call with variables.** The difference is
> Crossplane runs the "module" continuously, not just on `apply`.
