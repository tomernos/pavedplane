# Contributing to PavedPlane

PavedPlane is modular: the **APIs are cloud-neutral**, and each cloud is a
**configuration module** that implements those APIs. Contributing a cloud (or a
new API) means satisfying a contract, not reinventing one.

## The module contract

1. **Don't change the API to fit your cloud.** The XRDs in `apis/` are the shared
   contract (`XNetwork`, `XStorage`, later `XEnvironment`). Every cloud module
   must accept the same `spec`. If your cloud genuinely needs a new field, propose
   it as an *optional* field so other modules stay valid.
2. **One Composition per API, per cloud**, living under `configuration-<cloud>/`.
   Its `compositeTypeRef` points at the shared XRD; it renders that cloud's
   Managed Resources.
3. **Same `refName` pattern.** Cross-references resolve via label selectors on
   `platform.example.org/{xr,<parent>}` — never hard-code cloud IDs.
4. **Opinionated, safe defaults.** PavedPlane is a *paved road*: secure-by-default
   (e.g. uniform bucket access, public-access prevention, least-privilege IAM).

## Adding a new cloud module

```
cp -r module-template configuration-<cloud>      # e.g. configuration-azure
```
Then:
1. Add the cloud's provider package(s) to `configuration-<cloud>/providers.yaml`.
2. Write `configuration-<cloud>/compositions/xnetwork.yaml` (and `xstorage.yaml`)
   whose `compositeTypeRef` is the shared `apis/` XRD, rendering that cloud's MRs.
3. Provide `configuration-<cloud>/examples/` and a `create-sa`/credentials helper.
4. **Validate before PR:** `crossplane render <example> <composition> core/functions.yaml`.

## Selecting a cloud at runtime

Two supported patterns:
- **Composition selector** — label your Composition `cloud: <cloud>` and have the
  XR select it via `spec.compositionSelector.matchLabels.cloud`.
- **`spec.cloud` field** (planned on the shared XRDs) — a single field the XR sets,
  matched to the right Composition.

## House rules (learned the hard way — see docs/wiki/07)

- Set `deletionPolicy: Orphan` on live MRs before any provider upgrade.
- Pin every provider-family member to the **same** version.
- Pin the API version in tooling when a CRD has a conversion webhook.
- Never right-trim (`-}}`) immediately before a `---` in go-templates.
- Re-check `forProvider` block shapes (`kubectl explain … --api-version=…`) after a
  provider version bump.

## Style

- Compositions use **Pipeline mode** with `function-go-templating` +
  `function-auto-ready`.
- Keep templates readable; comment each section; give every emitted resource a
  unique `gotemplating.fn.crossplane.io/composition-resource-name`.
