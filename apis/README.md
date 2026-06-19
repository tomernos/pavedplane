# apis/ — the cloud-neutral contract

These `CompositeResourceDefinition`s (XRDs) define PavedPlane's APIs **once**,
independent of any cloud. Every cloud module (`configuration-gcp`,
`configuration-azure`, …) provides a Composition that satisfies these same XRDs,
so a consumer's `spec` is portable across clouds.

| API | Kind | What it provisions |
|---|---|---|
| `xnetwork/definition.yaml` | `XNetwork` | VPCs, subnets, NAT, firewall rules |
| `xstorage/definition.yaml` | `XStorage` | Object-storage buckets + bucket IAM |

Planned: `XEnvironment` — an umbrella API that composes the above (and later
compute/IAM/DNS) into one "give me a full environment" object.

**Rule:** changing these schemas affects *every* cloud module. Add cloud-specific
needs as optional fields so existing modules stay valid. See `../CONTRIBUTING.md`.
