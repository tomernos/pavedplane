# apis/ — the cloud-neutral contract

These `CompositeResourceDefinition`s (XRDs) define PavedPlane's APIs **once**,
independent of any cloud. Every cloud module (`configuration-gcp`,
`configuration-azure`, …) provides a Composition that satisfies these same XRDs,
so a consumer's `spec` is portable across clouds.

| API | Kind | What it provisions |
|---|---|---|
| `xenvironment/` | `XEnvironment` | **Umbrella** — one object → a full environment (network + storage) on `spec.cloud` |
| `xnetwork/definition.yaml` | `XNetwork` | VPCs, subnets, NAT, firewall rules |
| `xstorage/definition.yaml` | `XStorage` | Object-storage buckets + bucket IAM |

`XEnvironment` is **cloud-neutral**: it composes child `XNetwork` + `XStorage`
XRs and propagates `spec.cloud` to them via `compositionSelector` (so the consumer
picks the cloud once). Its Composition (`xenvironment/composition.yaml`) lives here
because it touches no cloud provider directly. Later it will also compose
compute/IAM/DNS. Example: `configuration-gcp/examples/xenvironment.yaml`.

**Rule:** changing these schemas affects *every* cloud module. Add cloud-specific
needs as optional fields so existing modules stay valid. See `../CONTRIBUTING.md`.
