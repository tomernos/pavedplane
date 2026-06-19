# 04 – XStorage (storage platform)

**API:** `platform.example.org/v1alpha1`, kind `XStorage`, cluster-scoped.
**Files:** `apis/xstorage/definition.yaml`, `apis/xstorage/composition.yaml`,
`examples/xstorage.yaml`.

## What one XStorage produces

| Spec array | Generated GCP Managed Resource | `refName` field |
|---|---|---|
| `buckets[]` | `Bucket` | `name` (target of `bucketRef`); also the **global** GCS name |
| `iamMembers[]` | `BucketIAMMember` | `bucketRef` → a `buckets[].name` |

> **GCS bucket names are globally unique across all of GCP.** So `external-name`
> is the literal `name` (no `xr` prefix) and you should prefix names with the
> project (e.g. `devopslab-tuzel-app-data`) to avoid collisions.

## Full bucket option surface

```yaml
buckets:
  - name: devopslab-tuzel-app-data
    location: US                         # US | EU | ASIA | region (us-central1)
    storageClass: STANDARD               # STANDARD | NEARLINE | COLDLINE | ARCHIVE
    forceDestroy: true                   # allow delete with objects present
    uniformBucketLevelAccess: true
    publicAccessPrevention: enforced     # enforced | inherited
    requesterPays: false
    defaultEventBasedHold: false
    versioning: true
    labels: { env: prod, team: platform }
    encryptionKmsKey: <kms-key>          # CMEK (optional)
    logging: { logBucket: <bkt>, logObjectPrefix: logs/ }
    website: { mainPageSuffix: index.html, notFoundPage: 404.html }
    retentionPolicy: { retentionPeriod: 2592000, isLocked: false }
    autoclass: { enabled: true, terminalStorageClass: ARCHIVE }
    softDeleteRetentionSeconds: 604800
    cors:
      - origin: ["*"]
        method: ["GET","HEAD"]
        responseHeader: ["Content-Type"]
        maxAgeSeconds: 3600
    lifecycleRules:
      - action: { type: SetStorageClass, storageClass: NEARLINE }
        condition: { age: 30 }
      - action: { type: Delete }
        condition: { numNewerVersions: 5, withState: ARCHIVED }

iamMembers:
  - name: site-public-read
    bucketRef: devopslab-tuzel-static-site   # must match a buckets[].name
    role: roles/storage.objectViewer
    member: allUsers
    condition: { title: ..., expression: ... }   # optional IAM condition
```

## How `refName` is wired

Buckets are labelled `platform.example.org/{xr,bucket}`; each `BucketIAMMember`
uses `bucketSelector.matchLabels` to bind to its bucket — same pattern as
[XNetwork](03-xnetwork.md).

## Important: schema shape depends on the provider version

The Composition currently targets provider **v2.4.1**, whose `Bucket` is
`storage.gcp.upbound.io/v1beta1`. In v1beta1 the singleton config blocks are
**Terraform-style single-element arrays**:

```yaml
versioning:
  - enabled: true          # array form (v1beta1)
```

In v1beta2 (shipped by v2.6.0) the same blocks became **maps**:

```yaml
versioning:
  enabled: true            # map form (v1beta2)
```

`cors` and `lifecycleRule` are arrays in both. If you change the provider
version, you must flip the Composition between array-form and map-form. See
[07 – Incidents](07-incidents-lessons.md).

## Gotchas (GCP-side)

- **Autoclass requires `storageClass: STANDARD`.** Setting COLDLINE/NEARLINE +
  autoclass is rejected (`Cannot set default storage class … other than STANDARD`).
- The service account needs **`roles/storage.admin`** (the network roles aren't
  enough) — `create-gcp-sa.sh` grants it.
- Listing buckets via `kubectl get bucket` (default version) **hangs** on this
  cluster — use `kubectl get buckets.v1beta1.storage.gcp.upbound.io`. Why: see
  the webhook section in [07](07-incidents-lessons.md).
