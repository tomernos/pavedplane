# Project Summary for an LLM (paste this whole file)

> **How to use this file:** Paste it into ChatGPT (or any LLM) and ask it to
> "explain this project to me step by step, like I'm learning Crossplane." It is
> self-contained — it includes the concepts, what was built, and what went wrong.
> I (the author) am an embedded/EE engineer growing into senior software/DevOps;
> explain trade-offs and the *why*, not just the *what*.

---

## 1. One-paragraph overview

I built a self-service infrastructure platform using **Crossplane v2.3** on a
local **Docker Desktop Kubernetes** cluster. It provisions **Google Cloud**
resources (VPC networking and Cloud Storage) from custom Kubernetes APIs. A user
applies one YAML object that contains **arrays** of resources (many VPCs, subnets,
NAT gateways, firewall rules, buckets, IAM bindings), and Crossplane creates and
continuously reconciles all of them in GCP. Cross-references between resources use
logical names (`refName`) resolved via label selectors, not cloud IDs.

## 2. The technologies, explained

- **Kubernetes**: the orchestrator. Here it's used not for apps but as a control
  plane for cloud infrastructure.
- **Crossplane**: an add-on that lets Kubernetes create/manage cloud resources
  with the same continuous-reconcile loop it uses for Pods. Install "providers"
  and it learns about `Network`, `Bucket`, etc.
- **Provider (Upjet GCP family)**: packages that add GCP resource types.
  I installed `provider-gcp-compute` and `provider-gcp-storage`, which share a
  `provider-family-gcp` package. (These are generated from Terraform via Upbound's
  "Upjet" — so the resource schemas mirror Terraform's GCP provider.)
- **Managed Resource (MR)**: a Kubernetes object that mirrors ONE cloud object
  (one `Bucket` = one GCS bucket). Crossplane keeps the cloud object matching it.
- **CompositeResourceDefinition (XRD)**: defines my OWN higher-level API
  (`XNetwork`, `XStorage`) and its schema.
- **Composition**: the recipe that turns one of my high-level objects into many
  MRs. It runs in "Pipeline mode" as a list of function steps.
- **Composition Functions**: small programs in the pipeline.
  `function-go-templating` renders MRs from a Go template (so it can LOOP over my
  arrays); `function-auto-ready` marks my object "Ready" when all its MRs are ready.
- **crossview**: a web dashboard for browsing Crossplane resources.

Mental model: **MR ≈ Terraform resource, Composition ≈ Terraform module,
the object I apply (XR) ≈ a module call with variables** — but reconciled
continuously, not just on apply.

## 3. What I actually built

Two custom APIs in the group `platform.example.org/v1alpha1`:

### XNetwork (networking)
```yaml
spec:
  projectID: devopslab-tuzel
  vpcs:          [{name, autoCreateSubnetworks, routingMode}]
  subnets:       [{name, vpcRef, region, ipCidrRange, privateIpGoogleAccess}]
  nats:          [{name, vpcRef, region, natIpAllocateOption, sourceSubnetworkIpRangesToNat}]
  firewallRules: [{name, vpcRef, direction, priority, sourceRanges, destinationRanges, allow:[{protocol,ports}]}]
```
- Each `vpcs[]` → a `Network`. Each `subnets[]` → a `Subnetwork`. Each `nats[]` →
  a `Router` **+** a `RouterNAT` (NAT needs a router). Each `firewallRules[]` → a
  `Firewall`.
- `vpcRef` points at a `vpcs[].name`. Implemented by labelling each Network with
  `{xr: <name>, vpc: <vpcName>}` and giving children a `networkSelector.matchLabels`.

### XStorage (storage)
```yaml
spec:
  projectID: devopslab-tuzel
  buckets:    [{name, location, storageClass, versioning, lifecycleRules, cors,
               encryptionKmsKey, logging, website, retentionPolicy, autoclass,
               softDeleteRetentionSeconds, uniformBucketLevelAccess,
               publicAccessPrevention, ...}]
  iamMembers: [{name, bucketRef, role, member, condition}]
```
- Each `buckets[]` → a `Bucket` (full GCS option surface). Each `iamMembers[]` →
  a `BucketIAMMember` bound to its bucket via `bucketSelector.matchLabels`.
- GCS bucket names are globally unique, so they're prefixed with the project id.

### How the array-looping works (the core trick)
The Composition's go-template iterates each spec array and prints one YAML
document (separated by `---`) per item. Each gets a unique
`gotemplating.fn.crossplane.io/composition-resource-name` annotation (or
Crossplane collapses duplicates). Validated locally with `crossplane render`.

## 4. The hard problems I hit (and what I learned)

1. **A provider upgrade (v2.4.1 → v2.6.0) deleted my live GCP network.** v2.6.0
   changed the CRDs; with the default `deletionPolicy: Delete`, the churn tore
   down real VPCs. **Lesson:** set `deletionPolicy: Orphan` before risky provider
   ops; treat upgrades like migrations.

2. **A broken conversion webhook.** v2.6.0 CRDs have two versions (`v1beta1`,
   `v1beta2`) with a conversion webhook served by the provider pod on `:9443`.
   On my Docker Desktop VM that webhook never responds, so `kubectl get bucket`
   and crossview hang. **Insight:** conversion only fires when the requested
   version ≠ the stored version, so pinning the version (`buckets.v1beta1...`)
   avoids it. I downgraded to v2.4.1 (where `v1beta1` is the storage version) so
   operations work; crossview still can't show buckets because it queries the
   preferred `v1beta2`.

3. **Schema shape changed between versions.** v1beta1 wraps singleton blocks as
   single-element arrays (`versioning: [{enabled: true}]`); v1beta2 uses maps
   (`versioning: {enabled: true}`). The Composition's YAML is coupled to the
   provider version.

4. **Go-template whitespace bug.** `{{- … -}}` right-trim before a `---` deleted
   the newline and produced invalid YAML. Fix: left-trim only before separators.

5. **GCP specifics:** Autoclass buckets must be `STANDARD` class; a VPC won't
   delete until its auto-created default route is removed; the service account
   needs `roles/storage.admin` for buckets (compute roles aren't enough); a
   Workspace org reauth policy blocked non-interactive `gcloud`.

## 5. Current state

- Crossplane core + functions + crossview installed; GCP providers pinned to
  v2.4.1.
- Platform APIs (`XNetwork`, `XStorage`) and Compositions applied.
- Demo resources were deployed, verified in GCP, then **torn down** (project is
  clean). The repo is the reusable definition; re-apply the examples to redeploy.

## 6. Questions I'd like the LLM to help me understand
- The difference between Crossplane v1 (claims) and v2 (namespaced/cluster XRs).
- When to use a conversion webhook at all, and how to run one reliably.
- Whether `deletionPolicy`, `managementPolicies`, and `Usage` would have
  prevented the deletion incident.
- How this compares to doing the same thing in Terraform, and the trade-offs.
