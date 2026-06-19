# 06 – Operations & Troubleshooting

## Install from scratch

```bash
# 1. Crossplane core
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm install crossplane crossplane-stable/crossplane \
  -n crossplane-system --create-namespace --wait

# 2. Providers + functions
kubectl apply -f bootstrap/01-providers.yaml
kubectl apply -f bootstrap/02-functions.yaml
kubectl wait --for=condition=Healthy --timeout=5m \
  provider.pkg.crossplane.io --all function.pkg.crossplane.io --all

# 3. GCP credentials (creates SA, grants roles, loads key as a Secret)
bash bootstrap/create-gcp-sa.sh        # run after: gcloud auth login
kubectl apply -f bootstrap/03-providerconfig.yaml

# 4. Platform APIs
kubectl apply -f apis/xnetwork/definition.yaml -f apis/xnetwork/composition.yaml
kubectl apply -f apis/xstorage/definition.yaml -f apis/xstorage/composition.yaml

# 5. Use it
kubectl apply -f examples/xnetwork.yaml
kubectl apply -f examples/xstorage.yaml
```

## Getting the objects (what's deployed)

```bash
kubectl get xnetwork,xstorage                 # the composites you applied
kubectl get composite                         # every XR
kubectl get xstorage demo-storage -o yaml     # full object
kubectl get xrd,composition                   # the platform API
kubectl get providers.pkg.crossplane.io
kubectl get functions.pkg.crossplane.io
kubectl get providerconfig.gcp.upbound.io

# Managed resources — ALWAYS use the explicit v1beta1 form on this cluster:
kubectl get buckets.v1beta1.storage.gcp.upbound.io
kubectl get network.v1beta1.compute.gcp.upbound.io
# everything composed by one XR (via our label):
kubectl get buckets.v1beta1.storage.gcp.upbound.io -l platform.example.org/xr=demo-storage
```

## ⚠️ The conversion-webhook hang (most important operational gotcha)

These commands **hang** on this cluster:
```bash
kubectl get managed        # ❌
kubectl get bucket         # ❌ (defaults to v1beta2 → broken conversion webhook)
```
Cause: the provider CRDs serve two versions (`v1beta1` storage + `v1beta2`), with
a conversion webhook the provider pod doesn't reliably answer. Discovery prefers
`v1beta2`, so any default-version access tries to convert via the dead webhook.

**Workaround:** always pin the version, e.g.
`kubectl get buckets.v1beta1.storage.gcp.upbound.io`. crossview, which queries the
preferred version, therefore shows compute MRs (their storage version is v1beta1)
but not buckets. Full story in [07](07-incidents-lessons.md).

## crossview UI

```bash
kubectl port-forward -n crossview svc/crossview-service 8080:80
# http://localhost:8080    (default login admin/password — ROTATE before exposing)
```
After installing/upgrading any provider, **restart crossview** so it re-discovers
the managed-resource CRDs: `kubectl rollout restart deploy/crossview -n crossview`.

## Teardown (delete deployed cloud resources)

```bash
# Delete composites — cascades to their MRs → deletes the GCP resources
kubectl delete xstorage --all
kubectl delete xnetwork --all

# Delete MRs explicitly if orphaned (use v1beta1):
kubectl delete buckets.v1beta1.storage.gcp.upbound.io --all
kubectl delete network.v1beta1.compute.gcp.upbound.io --all
```
**VPC won't delete?** Remove its GCP auto-route first:
```bash
gcloud compute routes list --project <p> --filter="network~<vpc>" --format='value(name)' \
  | xargs gcloud compute routes delete --project <p> --quiet
```

## Common errors → fixes

| Symptom | Cause | Fix |
|---|---|---|
| MR `Synced=False`: `ProviderConfig "default" not found` | creds not applied | `kubectl apply -f bootstrap/03-providerconfig.yaml` |
| MR `403 storage.buckets.create denied` | SA missing storage role | grant `roles/storage.admin` (in `create-gcp-sa.sh`) |
| `kubectl get bucket` hangs | conversion webhook | use `…buckets.v1beta1.storage.gcp.upbound.io` |
| VPC delete stuck `already being used by routes/...` | GCP default route | delete the route, then the VPC drops |
| Provider `Healthy=False`: `incompatible dependencies` | family version skew | pin family + all sub-providers to the **same** version |
| Image pull `unexpected EOF` | flaky Docker Desktop VM pull | `kubectl delete pod <stuck>` to reset backoff |
