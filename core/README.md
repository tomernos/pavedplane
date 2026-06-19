# core/ — cloud-agnostic cluster bootstrap

Things every PavedPlane install needs, regardless of cloud.

- `functions.yaml` — the composition functions used by all modules:
  - `function-go-templating` — loops over the spec arrays to render resources.
  - `function-auto-ready` — marks a composite Ready once its resources are Ready.

Install order: Crossplane core (Helm) → `core/functions.yaml` → a cloud module
(`configuration-<cloud>/`). See the root `README.md` quickstart.
