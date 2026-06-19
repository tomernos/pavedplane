# 07 – Incidents & Lessons Learned

This project hit several real problems. Documenting them is the most useful part
of the wiki — each one became a rule.

## Incident 1 — The v2.6.0 upgrade deleted live GCP resources

**What happened.** The GCP providers were upgraded from `v2.4.1` to `v2.6.0`
while a working `XNetwork` (3 VPCs, subnets, NAT, firewalls) was live. During the
CRD transition the existing managed resources were torn down and the **real GCP
VPCs/subnets/firewalls were deleted**.

**Why.** v2.6.0 introduced namespaced MR API groups (`*.gcp.m.crossplane.io`) and
rewrote the CRDs (added a `v1beta2` version + a conversion webhook). The
upgrade's CRD churn, combined with managed resources whose default
`deletionPolicy` is **`Delete`**, let the old controller process deletions
against GCP.

**Lessons.**
- **Never upgrade a provider across a major API/CRD change on a live deployment
  without `deletionPolicy: Orphan` set first.**
- Treat provider upgrades like database migrations: stage them, read the release
  notes for CRD/version changes, test on throwaway resources.
- `deletionPolicy: Orphan` is your seatbelt — it detaches the MR without deleting
  the cloud object.

## Incident 2 — The broken conversion webhook

**Symptom chain.** After v2.6.0:
- `kubectl get bucket` / `kubectl get managed` **hang**.
- The Composition couldn't apply MRs (`conversion webhook … connect: connection
  refused` / timeout on `:9443`).
- crossview showed **0 managed resources**.

**Root cause.** v2.6.0's CRDs have two served versions (`v1beta1`, `v1beta2`) with
`conversion: Webhook` pointing at the provider pod's `/convert` endpoint on
`:9443`. On this Docker Desktop cluster the API-server→pod webhook call never
completes (consistent with the VM's networking instability — image-pull EOFs, API
`connection reset`, leader-election failures seen all session). Any access to a
*non-storage* version triggers conversion → hang.

**Key insight.** Conversion only fires when the requested version ≠ the stored
version. So:
- Targeting the **storage version directly** sidesteps the webhook. For v2.6.0
  storage that was `v1beta2`; we switched the Composition to emit `v1beta2` and
  buckets deployed.
- After downgrading to v2.4.1, the storage version is `v1beta1`, so normal
  create/list/adopt works — but crossview still queries the *preferred* (highest)
  version `v1beta2`, which needs the webhook → buckets stay hidden in the UI.

**Lessons.**
- A broken conversion webhook poisons *every* default-version access to that CRD.
- When in doubt, **pin the version** in `kubectl` (`...buckets.v1beta1.storage...`).
- Webhooks need reliable in-cluster networking; resource-starved local VMs are a
  common failure point.

## Incident 3 — v1beta1 vs v1beta2 schema shape

**Symptom.** Applying buckets at v1beta2 errored: `expected map, got [array]` for
`versioning`, `lifecycleRule.action`, etc.

**Cause.** Upjet modernized the schema between versions:
- **v1beta1:** singleton blocks are Terraform-style **single-element arrays**
  (`versioning: [{enabled: true}]`).
- **v1beta2:** the same blocks are **maps** (`versioning: {enabled: true}`).
- `cors` and `lifecycleRule` stay arrays in both; in v1beta2 their sub-blocks
  (`action`, `condition`) are maps.

**Lesson.** The Composition's YAML shape is **coupled to the provider CRD
version**. Changing the provider version means re-checking every nested block
with `kubectl explain <resource>.spec.forProvider.<field> --api-version=...`.

## Incident 4 — Go-templating ate the `---` separator

**Symptom.** Render failed: `did not find expected key` / `did not find expected
'-' indicator`, only the first resource emitted.

**Cause.** Section comments used `{{- /* … */ -}}`. The trailing `-}}` trimmed the
newline before the next `---`, gluing the previous resource's last line onto the
separator.

**Lesson.** Never right-trim (`-}}`) immediately before a `---`. Use left-trim
only (`{{- /* … */}}`). Always validate with `crossplane render` before applying.

## Incident 5 — The downgrade left "dirty" CRDs

**Symptom.** After downgrading to v2.4.1, the Bucket CRD still showed `v1beta2` +
`conversion=Webhook`; manual patches reverted; the CRD even recreated dirty after
deletion.

**Cause.** Server-side apply doesn't *remove* fields a previous manager (v2.6.0
revision) added, and the v2.4.1 provider package itself ships the dual-version
CRD. Also a stuck CRD deletion: MRs with the `finalizer.managedresource.crossplane.io`
couldn't be processed while the CRD/controller was terminating (deadlock).

**Lessons.**
- Provider downgrades don't cleanly "undo" CRD schema changes — plan to recreate
  CRDs (with MRs orphaned first) if you must.
- A terminating CRD + MR finalizers deadlocks; break it by clearing finalizers on
  orphaned MRs (`kubectl patch … -p '{"metadata":{"finalizers":[]}}'`).

## Standing rules distilled from all of the above

1. `deletionPolicy: Orphan` before any risky provider operation on live infra.
2. Pin **all** provider-family members to one version; never let them skew.
3. Pin the `kubectl`/automation API version when a CRD has a conversion webhook.
4. Validate Compositions with `crossplane render` before `kubectl apply`.
5. Never right-trim before `---` in go-templates.
6. Re-check `forProvider` block shapes (`kubectl explain`) after a version bump.
7. On a flaky local cluster, expect webhook/networking failures; prefer a healthy
   VM (more CPU/RAM) or a real cluster for webhook-dependent providers.
