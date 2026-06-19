# module-template

Scaffold for a new PavedPlane cloud module. Copy this folder to
`configuration-<cloud>/` and fill it in.

```
configuration-<cloud>/
├── providers.yaml        # the cloud's Crossplane provider package(s)
├── providerconfig.yaml   # credentials/project binding for that cloud
├── create-sa.sh          # helper to create the service principal / SA + load creds
├── compositions/
│   ├── xnetwork.yaml      # Composition: compositeTypeRef = apis/xnetwork XRD
│   └── xstorage.yaml
└── examples/
    ├── xnetwork.yaml
    └── xstorage.yaml
```

## Steps
1. `cp -r module-template configuration-<cloud>`
2. Fill `providers.yaml` with the cloud's provider package(s); pin all
   family members to one version.
3. Write each Composition against the **shared** `apis/<api>/definition.yaml` —
   do not redefine the API. Render the cloud's Managed Resources from the same
   `spec` arrays, wiring `refName` via label selectors.
4. Add examples and a credentials helper.
5. Validate: `crossplane render examples/xnetwork.yaml compositions/xnetwork.yaml ../core/functions.yaml`
6. Open a PR. See [../CONTRIBUTING.md](../CONTRIBUTING.md).

## Composition skeleton

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: xnetwork-<cloud>
  labels:
    cloud: <cloud>            # lets an XR select this cloud via compositionSelector
spec:
  compositeTypeRef:
    apiVersion: platform.example.org/v1alpha1
    kind: XNetwork            # the SHARED API — unchanged
  mode: Pipeline
  pipeline:
    - step: render-resources
      functionRef: { name: function-go-templating }
      input:
        apiVersion: gotemplating.fn.crossplane.io/v1beta1
        kind: GoTemplate
        source: Inline
        inline:
          template: |
            {{- $xr := .observed.composite.resource }}
            {{- range $vpc := $xr.spec.vpcs }}
            ---
            # emit this cloud's "network" Managed Resource here
            {{- end }}
    - step: ready
      functionRef: { name: function-auto-ready }
```
