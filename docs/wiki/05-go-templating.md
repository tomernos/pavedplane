# 05 – Go Templating Deep Dive

This is the engine that turns arrays into resources. Read this to understand (and
safely edit) the Compositions.

## The pipeline

```yaml
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
          ...one big Go template that prints YAML...
  - step: ready
    functionRef: { name: function-auto-ready }
```

The function runs the Go template (with **Sprig** helpers like `default`, `quote`,
`len`), splits the output on `---`, and treats each document as a desired
resource. `function-auto-ready` then marks the XR ready.

## Reading the observed XR

```gotemplate
{{- $xr := .observed.composite.resource }}
{{- $xrName := $xr.metadata.name }}
{{- $project := $xr.spec.projectID }}
{{- range $vpc := $xr.spec.vpcs }}
---
apiVersion: compute.gcp.upbound.io/v1beta1
kind: Network
...
{{- end }}
```

`.observed.composite.resource` is the live XR (spec + status). Everything you
emit between `---` markers becomes a Managed Resource.

## The three rules that make it work

### 1. Unique `composition-resource-name` per item
Every emitted resource **must** carry a unique annotation:
```gotemplate
metadata:
  annotations:
    gotemplating.fn.crossplane.io/composition-resource-name: {{ printf "vpc-%s" $vpc.name | quote }}
```
In a loop, if these collide, Crossplane treats them as the *same* resource and
keeps only the last — you silently lose all but one. Prefix by kind + name
(`vpc-prod`, `subnet-prod-us-central`, …).

### 2. `refName` = label + selector (no IDs)
Emit identifying labels on the "parent":
```gotemplate
labels:
  platform.example.org/xr:  {{ $xrName | quote }}
  platform.example.org/vpc: {{ $vpc.name | quote }}
```
…and have the "child" select it:
```gotemplate
networkSelector:
  matchLabels:
    platform.example.org/xr:  {{ $xrName | quote }}
    platform.example.org/vpc: {{ $subnet.vpcRef | quote }}
```
Upjet resolves the selector to the parent's external-name at reconcile time.
Scoping by the `xr` label keeps one XR's children from grabbing another XR's
parent of the same name.

### 3. Whitespace: never right-trim before a `---`
Go template trim markers: `{{-` trims whitespace *before*, `-}}` trims *after*.
A `-}}` immediately before a `---` **eats the newline the separator needs**, so
the previous resource's last line glues onto `---` → invalid YAML
(`did not find expected key`). Rule of thumb:

```gotemplate
{{- /* section comment */}}      ✅ left-trim only, keeps the newline
{{- /* section comment */ -}}    ❌ right-trim deletes the newline before ---
```

This bug cost real debugging time; see [07](07-incidents-lessons.md).

## Optional blocks

Use `{{- with $x }}` to emit a block only when the field is set:
```gotemplate
{{- with $b.encryptionKmsKey }}
encryption:
  defaultKmsKeyName: {{ . | quote }}
{{- end }}
```
For booleans, prefer explicit `default` over `with` (because `with false` skips):
```gotemplate
isLocked: {{ .isLocked | default false }}
```

## Writing status back to the XR
Emit a document whose GVK matches the composite; go-templating merges it into the
XR status:
```gotemplate
---
apiVersion: platform.example.org/v1alpha1
kind: XNetwork
status:
  vpcCount: {{ len ($xr.spec.vpcs | default list) }}
```

## Validate locally before applying
```bash
crossplane render configuration-gcp/examples/xnetwork.yaml configuration-gcp/compositions/xnetwork.yaml core/functions.yaml
```
This runs the functions in Docker against the example and prints the rendered
MRs — it catches template/YAML/indentation bugs without touching the cluster or GCP.
