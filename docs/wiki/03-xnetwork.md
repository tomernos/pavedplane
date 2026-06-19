# 03 – XNetwork (networking platform)

**API:** `platform.example.org/v1alpha1`, kind `XNetwork`, cluster-scoped.
**Files:** `apis/xnetwork/definition.yaml` (XRD), `configuration-gcp/compositions/xnetwork.yaml`
(Composition), `configuration-gcp/examples/xnetwork.yaml` (sample).

## What one XNetwork produces

| Spec array | Generated GCP Managed Resource(s) | `refName` field |
|---|---|---|
| `vpcs[]` | `Network` | `name` (target of `vpcRef`) |
| `subnets[]` | `Subnetwork` | `vpcRef` → a `vpcs[].name` |
| `nats[]` | `Router` **+** `RouterNAT` | `vpcRef` → a `vpcs[].name` |
| `firewallRules[]` | `Firewall` | `vpcRef` → a `vpcs[].name` |

One `nats[]` entry fans out to **two** MRs because Cloud NAT cannot exist without
a Cloud Router.

## Spec reference

```yaml
spec:
  projectID: <gcp-project>
  vpcs:
    - name: prod                       # refName + GCP network name
      autoCreateSubnetworks: false     # false = custom-mode VPC (recommended)
      routingMode: REGIONAL            # or GLOBAL
  subnets:
    - name: prod-us-central
      vpcRef: prod                     # must match a vpcs[].name
      region: us-central1
      ipCidrRange: 10.0.0.0/20
      privateIpGoogleAccess: true
  nats:
    - name: prod-nat-usc
      vpcRef: prod
      region: us-central1
      natIpAllocateOption: AUTO_ONLY
      sourceSubnetworkIpRangesToNat: ALL_SUBNETWORKS_ALL_IP_RANGES
  firewallRules:
    - name: prod-allow-ssh
      vpcRef: prod
      direction: INGRESS               # or EGRESS
      priority: 1000
      sourceRanges: ["35.235.240.0/20"]
      destinationRanges: []            # for EGRESS
      allow:
        - protocol: tcp
          ports: ["22"]
```

## How `refName` is wired

Every generated `Network` is labelled:
```yaml
labels:
  platform.example.org/xr:  <xr-name>     # e.g. demo
  platform.example.org/vpc: <vpcs[].name> # e.g. prod
```
A subnet/NAT/firewall with `vpcRef: prod` is rendered with a
`networkSelector.matchLabels` targeting `{xr: demo, vpc: prod}`. The Upjet
provider resolves that selector to the actual network at reconcile time. The
`xr` label scopes the match so one XNetwork can't accidentally select another's
VPC of the same name.

The actual GCP resource name is set via the `crossplane.io/external-name`
annotation = `<xr>-<name>` (e.g. `demo-prod`, `demo-prod-us-central`).

## Inspect a deployment

```bash
kubectl get xnetwork demo
# List MRs at the storage version v1beta1 (avoids the conversion-webhook hang):
kubectl get network.v1beta1.compute.gcp.upbound.io
kubectl get subnetwork.v1beta1.compute.gcp.upbound.io
kubectl get firewall.v1beta1.compute.gcp.upbound.io
```

## Gotchas (GCP-side)

- **Deleting a VPC fails while its auto-created default route exists.** GCP makes
  a `default-route-*` per network that Crossplane doesn't manage. Delete it first:
  `gcloud compute routes list --filter="network~<vpc>"` → delete, then the VPC drops.
- **Subnet CIDRs must not overlap** within a VPC and must fit the region.
- A **custom-mode** VPC (`autoCreateSubnetworks: false`) is almost always what you
  want; auto-mode creates a subnet in every region.
