# configuration-gcp — the GCP module

Implements PavedPlane's cloud-neutral APIs (`apis/`) on Google Cloud.

```
configuration-gcp/
├── providers.yaml        # Upjet GCP providers: family + compute + storage (pinned v2.4.1)
├── providerconfig.yaml   # ProviderConfig "default" → project + gcp-creds Secret
├── create-sa.sh          # creates the SA, grants roles, loads the key as a Secret
├── compositions/
│   ├── xnetwork.yaml      # Composition for XNetwork on GCP
│   └── xstorage.yaml      # Composition for XStorage on GCP
└── examples/             # sample XNetwork / XStorage resources
```

## Apply

```bash
kubectl apply -f configuration-gcp/providers.yaml
bash configuration-gcp/create-sa.sh        # after: gcloud auth login
kubectl apply -f configuration-gcp/providerconfig.yaml
kubectl apply -f configuration-gcp/compositions/xnetwork.yaml \
              -f configuration-gcp/compositions/xstorage.yaml
kubectl apply -f configuration-gcp/examples/xnetwork.yaml
```

## GCP-specific notes (full detail in `../docs/wiki/`)

- **Providers pinned to v2.4.1.** v2.6.0's conversion webhook is unreliable on
  Docker Desktop and an upgrade once deleted live resources. Orphan first.
- `kubectl get bucket` / `get managed` **hang** (webhook on preferred v1beta2) —
  use `kubectl get buckets.v1beta1.storage.gcp.upbound.io`.
- SA roles: `compute.networkAdmin`, `compute.securityAdmin`, `storage.admin`.
- Composition YAML targets the **v1beta1** schema (singleton blocks = single-element
  arrays). v1beta2 uses maps — re-check shapes if you bump the provider.
