#!/usr/bin/env bash
# Creates the Crossplane service account + key for the GCP provider and loads
# it into the cluster as a Secret. Run AFTER `gcloud auth login`.
#
# Least-privilege networking roles:
#   compute.networkAdmin  -> networks, subnets, routers, NAT, routes
#   compute.securityAdmin -> firewall rules
set -euo pipefail

PROJECT_ID="devopslab-tuzel"
SA_NAME="crossplane"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
KEY_FILE="/tmp/gcp-creds-${PROJECT_ID}.json"

gcloud config set project "${PROJECT_ID}"

# Required APIs (idempotent)
gcloud services enable compute.googleapis.com iam.googleapis.com \
  --project="${PROJECT_ID}"

# Service account (create only if missing)
if ! gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${SA_NAME}" \
    --project="${PROJECT_ID}" \
    --display-name="Crossplane GCP provider"
fi

# Role bindings (idempotent)
#   compute.networkAdmin/securityAdmin -> VPCs, subnets, routers, NAT, firewalls
#   storage.admin                      -> GCS buckets + bucket IAM
for ROLE in roles/compute.networkAdmin roles/compute.securityAdmin roles/storage.admin; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${ROLE}" \
    --condition=None >/dev/null
done

# Key
gcloud iam service-accounts keys create "${KEY_FILE}" \
  --iam-account="${SA_EMAIL}"

# Load into the cluster (recreate if it already exists)
kubectl create secret generic gcp-creds \
  -n crossplane-system \
  --from-file=credentials.json="${KEY_FILE}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Shred the local key — it now lives only in the cluster Secret
shred -u "${KEY_FILE}" 2>/dev/null || rm -f "${KEY_FILE}"

echo "Done. SA=${SA_EMAIL}, secret gcp-creds created in crossplane-system."
