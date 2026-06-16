# EKS Migration — End-to-End Workload Migration

A complete, production-grade blueprint for deploying a workload on an EKS cluster and migrating it to a second EKS cluster with near-zero downtime.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Repository Structure](#repository-structure)
3. [Prerequisites](#prerequisites)
4. [Phase 1 — Cluster 1 Setup & Application Deployment](#phase-1--cluster-1-setup--application-deployment)
   - [Step 1 · Bootstrap Terraform State Backend](#step-1--bootstrap-terraform-state-backend)
   - [Step 2 · Deploy Cluster 1 Infrastructure](#step-2--deploy-cluster-1-infrastructure)
   - [Step 3 · Build & Push the Docker Image](#step-3--build--push-the-docker-image)
   - [Step 4 · Bootstrap ArgoCD](#step-4--bootstrap-argocd)
   - [Step 5 · Wire up Route 53](#step-5--wire-up-route-53)
   - [Step 6 · Verify the Application](#step-6--verify-the-application)
5. [Phase 2 — Cluster 2 Setup & Migration](#phase-2--cluster-2-setup--migration)
   - [Step 7 · Deploy Cluster 2 Infrastructure](#step-7--deploy-cluster-2-infrastructure)
   - [Step 8 · Create a Velero Backup](#step-8--create-a-velero-backup)
   - [Step 9 · Restore to Cluster 2](#step-9--restore-to-cluster-2)
   - [Step 10 · Progressive Traffic Shift](#step-10--progressive-traffic-shift)
   - [Step 11 · Final Cutover](#step-11--final-cutover)
   - [Step 12 · Decommission Cluster 1](#step-12--decommission-cluster-1)
6. [Key Design Decisions](#key-design-decisions)
7. [GitHub Secrets Reference](#github-secrets-reference)
8. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
Internet
    │
    ▼
Route 53 (weighted CNAME)
    │
    ├─── weight=100 ──► NLB (cluster1) ──► Istio IngressGateway ──► taskmanager pods
    │
    └─── weight=0   ──► NLB (cluster2) ──► Istio IngressGateway ──► taskmanager pods
                                                                              │
                                                        VPC Peering ──► RDS PostgreSQL
```

### Components

| Layer | Technology | Notes |
|---|---|---|
| Compute | EKS Auto Mode | Managed node provisioning, no node groups |
| Database | RDS PostgreSQL 16 | Multi-AZ, storage-encrypted, shared between clusters during migration |
| Secrets | AWS Secrets Manager + External Secrets Operator | DB credentials never in Git |
| Service mesh | Istio | TLS termination, traffic routing |
| TLS certificates | cert-manager + Let's Encrypt (DNS-01) | Free, auto-renewed, Route 53 integration |
| GitOps | ArgoCD | Automated sync from this repository |
| Backup | Velero + S3 + EBS snapshots | Daily scheduled + pre-migration snapshot |
| DNS | Route 53 weighted routing | Progressive traffic shift during migration |
| Workload identity | EKS Pod Identity | No IRSA OIDC complexity |
| CI/CD | GitHub Actions | 5 workflows covering infra, build, deploy, migrate |

---

## Repository Structure

```
eks-migration/
├── infra/
│   ├── bootstrap/          # One-time: S3 bucket + DynamoDB for TF state
│   ├── modules/
│   │   ├── vpc/            # VPC, subnets (3 AZ), NAT gateways, route tables
│   │   ├── eks/            # EKS Auto Mode cluster, IAM roles, Pod Identity addon
│   │   ├── rds/            # RDS PostgreSQL, subnet group, security group
│   │   ├── secrets-manager/ # Secrets Manager secret for DB credentials
│   │   ├── s3/             # Velero backup S3 bucket + lifecycle rules
│   │   ├── iam/            # IAM roles + EKS Pod Identity associations
│   │   ├── route53/        # Weighted CNAME records + health check
│   │   └── addons/         # Helm releases: cert-manager, Istio, ESO, ArgoCD, Velero
│   ├── cluster1/           # Phase 1: full infrastructure composition
│   └── cluster2/           # Phase 2: second cluster + VPC peering
├── app/                    # Node.js Task Manager application
│   ├── src/
│   │   ├── index.js        # Express server, /health, /ready, /metrics
│   │   ├── routes/tasks.js # CRUD + file upload endpoints
│   │   ├── db/client.js    # pg Pool + auto-migrate
│   │   └── public/         # Single-page HTML frontend
│   ├── Dockerfile          # Multi-stage, non-root, dumb-init
│   └── package.json
├── helm/taskmanager/       # Helm chart
│   ├── values.yaml         # Default values (cluster1)
│   ├── values-cluster2.yaml # Overrides for cluster2
│   └── templates/          # Deployment, Service, ConfigMap, ExternalSecret,
│                           # PVC, ServiceAccount, Gateway, VirtualService, HPA, PDB
├── argocd/                 # ArgoCD Project + Application manifests
├── migration/              # Migration scripts
│   ├── 01-backup.sh        # Velero backup from cluster1
│   ├── 02-restore.sh       # Velero restore to cluster2
│   ├── 03-traffic-shift.sh # Update Route 53 weights via Terraform
│   └── 04-cutover.sh       # Final cutover + cluster1 drain
├── scripts/
│   ├── bootstrap-tfstate.sh
│   └── setup-kubeconfig.sh
└── .github/workflows/
    ├── 01-infra-cluster1.yml
    ├── 02-app-build.yml
    ├── 03-argocd-bootstrap.yml
    ├── 04-infra-cluster2.yml
    └── 05-migration.yml
```

---

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Terraform | >= 1.6 | Infrastructure provisioning |
| AWS CLI | >= 2.x | Authentication, kubeconfig |
| kubectl | >= 1.29 | Cluster management |
| helm | >= 3.15 | Chart linting (addons installed via Terraform) |
| velero CLI | >= 1.15 | Backup management |
| jq | any | JSON parsing in scripts |

**AWS permissions** — The IAM user/role running Terraform needs:
- `eks:*`, `ec2:*`, `rds:*`, `s3:*`
- `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:PassRole`
- `secretsmanager:*`, `route53:*`, `acm:*`

**Docker Hub** — A repository named `simoganger/taskmanager` (create it at hub.docker.com).

---

## Phase 1 — Cluster 1 Setup & Application Deployment

### Step 1 · Bootstrap Terraform State Backend

Run this **once** before any other Terraform command:

```bash
export AWS_REGION=us-east-1
export TF_STATE_BUCKET=eks-migration-tfstate

./scripts/bootstrap-tfstate.sh
```

This creates the S3 bucket and DynamoDB table that all subsequent `terraform init` commands will use.

---

### Step 2 · Deploy Cluster 1 Infrastructure

**Option A — GitHub Actions (recommended):**

1. Add all [required secrets](#github-secrets-reference) to your GitHub repository.
2. Push changes to `infra/cluster1/` or trigger **01 · Infrastructure Cluster 1** manually with action = `apply`.

**Option B — Local:**

```bash
cd infra/cluster1
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set db_password, acme_email, admin_role_arns

terraform init
terraform plan
terraform apply
```

This single `terraform apply` creates (in order):
- VPC with 3 public + 3 private subnets across 3 AZs, NAT gateways
- EKS Auto Mode cluster (`eks-cluster-1`, Kubernetes 1.32)
- RDS PostgreSQL 16 (Multi-AZ, encrypted)
- AWS Secrets Manager secret (`/prod/taskmanager/db`)
- S3 bucket for Velero backups
- IAM roles with EKS Pod Identity associations for app, ESO, Velero, cert-manager
- Route 53 weighted CNAME (weight=100 on cluster1, no cluster2 record yet)
- Helm releases: cert-manager → ClusterIssuer → Certificate, Istio (base + istiod + ingress gateway), External Secrets Operator → ClusterSecretStore, ArgoCD, Velero

> **Two-phase apply note:** The Istio IngressGateway NLB hostname is only known after the first apply. Once provisioned, set `istio_lb_hostname` in `terraform.tfvars` and re-apply to wire Route 53.

```bash
# After first apply, get the NLB hostname:
kubectl get svc -n istio-system istio-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Update terraform.tfvars:
# istio_lb_hostname = "xxxxxx.elb.us-east-1.amazonaws.com"

terraform apply  # second pass, only updates Route 53
```

---

### Step 3 · Build & Push the Docker Image

**GitHub Actions** (auto-triggered on push to `app/**`):

Push any change to `app/` — workflow `02-app-build` builds the multi-stage Docker image and pushes:
- `simoganger/taskmanager:<sha>`
- `simoganger/taskmanager:latest`

It then commits the new tag back to `helm/taskmanager/values.yaml` so ArgoCD picks it up automatically.

**Manual:**

```bash
cd app
docker build -t simoganger/taskmanager:latest .
docker push simoganger/taskmanager:latest
```

---

### Step 4 · Bootstrap ArgoCD

```bash
./scripts/setup-kubeconfig.sh cluster1

# Wait for ArgoCD pods to be ready:
kubectl wait pod -n argocd -l app.kubernetes.io/name=argocd-server \
  --for=condition=Ready --timeout=300s

# Apply ArgoCD Project and Application:
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/app-cluster1.yaml
```

Or trigger **03 · ArgoCD Bootstrap** in GitHub Actions selecting `cluster1`.

ArgoCD will automatically sync the Helm chart and deploy `taskmanager` into the `taskmanager` namespace (which already has Istio sidecar injection enabled from the addons module).

**Access ArgoCD UI:**

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Initial admin password:
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
# Open: https://localhost:8080
```

---

### Step 5 · Wire up Route 53

After both the Istio NLB and cert-manager Certificate are ready:

```bash
# Check certificate is issued:
kubectl get certificate -n istio-system taskmanager-tls

# Check Istio Gateway:
kubectl get gateway -n taskmanager

# DNS record should already point to the NLB via Terraform.
# Verify:
dig app.navelmountech.com
```

---

### Step 6 · Verify the Application

```bash
# All pods should be Running (2 replicas):
kubectl get pods -n taskmanager

# ExternalSecret should be Synced:
kubectl get externalsecret -n taskmanager

# Test endpoints:
curl https://app.navelmountech.com/health
curl https://app.navelmountech.com/ready
curl https://app.navelmountech.com/api/tasks

# Full UI:
open https://app.navelmountech.com
```

---

## Phase 2 — Cluster 2 Setup & Migration

### Step 7 · Deploy Cluster 2 Infrastructure

```bash
cd infra/cluster2
cp terraform.tfvars.example terraform.tfvars
# Edit: set acme_email — leave weights at 100/0 for now

terraform init
terraform apply
```

This creates:
- A **separate VPC** (`10.1.0.0/16`, does not overlap with cluster1's `10.0.0.0/16`)
- **VPC Peering** connection from cluster2 VPC → cluster1 VPC
- Routes in both VPCs + a new inbound rule in the **RDS Security Group** allowing `10.1.0.0/16`
- EKS Auto Mode cluster (`eks-cluster-2`)
- Same addon stack as cluster1 (ArgoCD, ESO, Istio, Velero, cert-manager)
- ArgoCD Application pointing at `helm/taskmanager/values.yaml` + `values-cluster2.yaml`
- Route 53: cluster1 weight=100, cluster2 weight=0 (no traffic yet)

```bash
# After apply, get cluster2 NLB hostname:
kubectl config use-context cluster2
kubectl get svc -n istio-system istio-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Set in terraform.tfvars:
# istio_lb_hostname    = "yyyy.elb.us-east-1.amazonaws.com"
# cluster1_lb_hostname = "xxxx.elb.us-east-1.amazonaws.com"  # from cluster1 output
terraform apply  # updates Route 53 with cluster2 record at weight=0
```

---

### Step 8 · Create a Velero Backup

```bash
kubectl config use-context cluster1
./migration/01-backup.sh
# Or: trigger 05-migration workflow, step = 01-backup
```

Velero creates a backup of the `taskmanager` namespace including EBS volume snapshots. The backup lands in the shared S3 bucket (`eks-cluster-1-velero-backups`).

---

### Step 9 · Restore to Cluster 2

Configure Velero on cluster2 to read from cluster1's S3 bucket, then restore:

```bash
# cluster2 Velero already points at the same S3 bucket (via shared module variable)
kubectl config use-context cluster2
./migration/02-restore.sh
# Or: trigger 05-migration workflow, step = 02-restore
```

Verify pods are running on cluster2:

```bash
kubectl get pods -n taskmanager
kubectl exec -n taskmanager deploy/taskmanager -- wget -qO- http://localhost:3000/ready
```

---

### Step 10 · Progressive Traffic Shift

**Important:** Monitor error rates in CloudWatch or your observability stack between each shift. Wait at least 5–10 minutes before the next shift.

```
Shift 1:  cluster1=90  cluster2=10
Shift 2:  cluster1=70  cluster2=30
Shift 3:  cluster1=50  cluster2=50
Shift 4:  cluster1=10  cluster2=90
```

**Via GitHub Actions** (recommended for auditability):

Trigger **05 · Migration**, choose step `03-shift-10`, `03-shift-30`, `03-shift-50`, or `03-shift-90`.

**Manually:**

```bash
CLUSTER1_WEIGHT=90 CLUSTER2_WEIGHT=10 ./migration/03-traffic-shift.sh
# Monitor for 10 min, then:
CLUSTER1_WEIGHT=70 CLUSTER2_WEIGHT=30 ./migration/03-traffic-shift.sh
# ...and so on
```

**Monitoring commands:**

```bash
# Watch request distribution (from access logs or metrics)
kubectl logs -n taskmanager -l app.kubernetes.io/name=taskmanager -f --context=cluster1
kubectl logs -n taskmanager -l app.kubernetes.io/name=taskmanager -f --context=cluster2

# Check DB connections from each cluster
kubectl exec -n taskmanager deploy/taskmanager --context=cluster2 -- \
  node -e "require('./src/db/client').pool.query('SELECT count(*) FROM tasks').then(r => console.log(r.rows))"
```

---

### Step 11 · Final Cutover

After validating cluster2 handles 90% of traffic without issues:

```bash
./migration/04-cutover.sh
# Or: trigger 05-migration workflow, step = 04-cutover
```

This:
1. Sets Route 53 weights to cluster1=0, cluster2=100
2. Scales down `taskmanager` deployment on cluster1 to 0 replicas
3. Creates a final archive Velero backup of cluster1

Run the final smoke test:

```bash
curl https://app.navelmountech.com/health
curl https://app.navelmountech.com/ready
curl -X GET https://app.navelmountech.com/api/tasks
```

---

### Step 12 · Decommission Cluster 1

After 24–48 hours of monitoring:

```bash
# Remove deletion protection from RDS first (or skip_final_snapshot = true):
# In terraform.tfvars: rds_deletion_protection = false
cd infra/cluster1
terraform apply  # removes deletion protection

terraform destroy  # destroys all cluster1 resources
```

> The RDS instance will remain (it's in cluster1's VPC). If you want to move it to cluster2's VPC, create a new RDS instance in cluster2's VPC, use pg_dump/pg_restore to migrate data, update the DB host in Secrets Manager, and let ESO sync the new secret.

---

## Key Design Decisions

### EKS Auto Mode

EKS Auto Mode (`compute_config.enabled = true`) removes the need to manage node groups, AMIs, or node lifecycle. AWS provisions, scales, and replaces nodes automatically. Built-in:
- AWS Load Balancer Controller (NLB/ALB provisioning)
- EBS CSI Driver (`storage_config.block_storage.enabled = true`)
- VPC CNI, CoreDNS, kube-proxy

### Certificate Management — cert-manager + Let's Encrypt

ACM certificates cannot be mounted as Kubernetes secrets and thus cannot be used for Istio TLS termination (ACM only works with ALB/NLB SSL listeners). cert-manager with Let's Encrypt DNS-01 challenge is the standard approach:
- DNS-01 via Route 53 (works for wildcard certs, no HTTP port 80 needed)
- cert-manager uses EKS Pod Identity to call Route 53 APIs
- Certificates auto-renew 30 days before expiry
- TLS secret is created in `istio-system` and referenced by the Istio Gateway

### EKS Pod Identity

Pod Identity (`aws_eks_pod_identity_association`) is the modern replacement for IRSA:
- No OIDC trust policy complexity
- Works via the `eks-pod-identity-agent` addon
- Four associations: `taskmanager`, `external-secrets`, `velero`, `cert-manager`

### Secrets Flow

```
AWS Secrets Manager (/prod/taskmanager/db)
        │  EKS Pod Identity
        ▼
External Secrets Operator (ClusterSecretStore)
        │  creates
        ▼
Kubernetes Secret (taskmanager-db-secret)
        │  envFrom.secretRef
        ▼
Pod environment variables (DB_USER, DB_PASSWORD)
```

### RDS During Migration

RDS lives in cluster1's VPC. During migration, VPC Peering gives cluster2 pods access to the same database — no data migration required. Both clusters write to the same DB simultaneously during the traffic shift window (acceptable because the application has no cross-request session state stored locally).

---

## GitHub Secrets Reference

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `AWS_ACCOUNT_ID` | 12-digit AWS account ID |
| `DOCKERHUB_USERNAME` | Docker Hub username (`simoganger`) |
| `DOCKERHUB_TOKEN` | Docker Hub access token (not password) |
| `DB_PASSWORD` | RDS master password (strong, never hardcoded) |
| `ACME_EMAIL` | Email for Let's Encrypt registration |
| `TF_STATE_BUCKET` | S3 bucket for Terraform state (`eks-migration-tfstate`) |
| `TF_STATE_LOCK_TABLE` | DynamoDB table name (`eks-migration-tfstate-lock`) |

---

## Troubleshooting

### Pods stuck in `Pending`

EKS Auto Mode provisions nodes on demand. New nodes take 2–3 minutes. Check:

```bash
kubectl get events -n taskmanager --sort-by='.lastTimestamp'
kubectl describe pod <pod-name> -n taskmanager
```

### ExternalSecret not syncing

```bash
kubectl describe externalsecret -n taskmanager
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets

# Check Pod Identity association is configured:
aws eks list-pod-identity-associations --cluster-name eks-cluster-1
```

### Certificate stuck in `False` / `Issuing`

```bash
kubectl describe certificate taskmanager-tls -n istio-system
kubectl describe certificaterequest -n istio-system
kubectl logs -n cert-manager -l app=cert-manager

# Verify Route 53 TXT record was created:
dig _acme-challenge.navelmountech.com TXT
```

### Istio sidecar not injecting

Verify the namespace has the injection label:

```bash
kubectl get namespace taskmanager -o jsonpath='{.metadata.labels}'
# Should contain: istio-injection=enabled
```

### Velero backup fails

```bash
velero backup logs pre-migration
kubectl logs -n velero -l app.kubernetes.io/name=velero

# Verify S3 access:
aws s3 ls s3://eks-cluster-1-velero-backups/
```

### Route 53 not resolving to new cluster

DNS TTL is set to 60 seconds. After a weight change, wait 60 seconds. Verify:

```bash
dig app.navelmountech.com
# Check the CNAME target matches the expected NLB
```
