# Project Bedrock — AltSchool Karatu 2025 Capstone

Production-grade AWS EKS deployment of the [AWS Retail Store Sample App](https://github.com/aws-containers/retail-store-sample-app), built as a capstone project for AltSchool Africa's Karatu 2025 cohort.

---

## Project Overview

Project Bedrock provisions and deploys a fully operational cloud-native e-commerce platform on AWS. The application is a microservices-based retail store with a frontend, product catalog, shopping cart, checkout flow, and order management — all running on Kubernetes with managed databases, automated secret synchronisation, and infrastructure-as-code.

The goal is to demonstrate production patterns that go far beyond a basic Kubernetes deployment:

- Infrastructure provisioned entirely with Terraform
- Secrets managed through AWS Secrets Manager and synchronised into Kubernetes automatically via External Secrets Operator
- IAM roles bound to Kubernetes service accounts (IRSA) — no static credentials, all created via Terraform
- Multi-service microservices application deployed with proper resource constraints
- CI/CD pipelines validating infrastructure and manifest changes on every push

---

## Architecture

```
                          ┌─────────────────────────────────────────┐
                          │              AWS us-east-1               │
                          │                                          │
  Internet ──────────────▶│  ALB (internet-facing)                  │
                          │     │                                    │
                          │     ▼                                    │
                          │  ┌──────────────────────────────────┐   │
                          │  │         EKS Cluster              │   │
                          │  │         retail-app namespace      │   │
                          │  │                                   │   │
                          │  │  ui ──▶ catalog ──▶ RDS MySQL    │   │
                          │  │      ──▶ carts   ──▶ DynamoDB    │   │
                          │  │      ──▶ checkout──▶ Redis        │   │
                          │  │      ──▶ orders  ──▶ RDS MySQL   │   │
                          │  │      ──▶ assets                  │   │
                          │  │                                   │   │
                          │  │  rabbitmq   redis                 │   │
                          │  └──────────────────────────────────┘   │
                          │                                          │
                          │  ┌──────────────────────────────────┐   │
                          │  │ RDS MySQL 8.0                    │   │
                          │  │  • orders database (orders svc)  │   │
                          │  │  • catalog database (catalog svc)│   │
                          │  └──────────────────────────────────┘   │
                          │                                          │
                          │  ┌────────────┐  ┌──────────────────┐  │
                          │  │  DynamoDB  │  │ Secrets Manager  │  │
                          │  │ (products) │  │ (DB credentials) │  │
                          │  └────────────┘  └──────────────────┘  │
                          └─────────────────────────────────────────┘
```

### VPC Layout

```
VPC: 10.0.0.0/16  (us-east-1)

  us-east-1a                  us-east-1b
  ┌────────────────┐          ┌────────────────┐
  │ Public subnet  │          │ Public subnet  │
  │ 10.0.101.0/24  │          │ 10.0.102.0/24  │
  │                │          │                │
  │  NAT Gateway   │          │                │
  └────────┬───────┘          └────────────────┘
           │
  ┌────────▼───────┐          ┌────────────────┐
  │ Private subnet │          │ Private subnet │
  │ 10.0.1.0/24    │          │ 10.0.2.0/24    │
  │ EKS nodes      │          │ EKS nodes      │
  │ RDS instances  │          │ RDS instances  │
  └────────────────┘          └────────────────┘
```

---

## Infrastructure Stack

All infrastructure is defined as code in the `terraform/` directory.

| Component | Technology | Details |
|---|---|---|
| Cloud Provider | AWS | Region: us-east-1 |
| Container Orchestration | Amazon EKS 1.33 | Managed node groups |
| Compute Nodes | EC2 t3.small | Managed node group, desired 4 nodes, min 2, max 5, ON_DEMAND capacity |
| Networking | VPC + Subnets + NAT | 2 AZs, public + private subnets |
| Relational DB (orders + catalog) | RDS MySQL 8.0 | db.t3.micro, 20GB gp3, encrypted at rest |
| Relational DB (provisioned) | RDS PostgreSQL 17 | db.t3.micro, 20GB gp3 — provisioned but not used by current app services |
| NoSQL DB | DynamoDB | PAY_PER_REQUEST billing |
| Secret Storage | AWS Secrets Manager | RDS native password management |
| Load Balancing | AWS ALB | Provisioned by ALB Controller |
| State Backend | S3 | Bucket: project-bedrock-tfstate-3152 |

### Terraform File Structure

```
terraform/
├── backend.tf        # S3 remote state
├── versions.tf       # Provider version constraints
├── providers.tf      # AWS provider with default tags
├── variables.tf      # Input variables
├── networking.tf     # VPC, subnets, NAT gateway
├── eks.tf            # EKS cluster and managed node groups
├── data-layer.tf     # RDS MySQL, RDS PostgreSQL, DynamoDB
├── irsa.tf           # IRSA roles for ALB controller, External Secrets, carts
└── outputs.tf        # Cluster endpoint, DB endpoints, secret ARNs, role ARNs
```

---

## Kubernetes Architecture

All application workloads run in the `retail-app` namespace.

### Microservices

| Service | Image | Backend | Port |
|---|---|---|---|
| `ui` | retail-store-sample-ui:0.8.5 | — | 8080 |
| `catalog` | retail-store-sample-catalog:0.8.5 | RDS MySQL (`catalog` database) | 8080 |
| `carts` | retail-store-sample-cart:0.8.5 | DynamoDB + Redis | 8080 |
| `orders` | retail-store-sample-orders:0.8.5 | RDS MySQL (`orders` database) | 8080 |
| `checkout` | retail-store-sample-checkout:0.8.5 | Redis | 8080 |
| `assets` | retail-store-sample-assets:0.8.5 | — | 8080 |
| `redis` | redis:7-alpine | — | 6379 |
| `rabbitmq` | rabbitmq:3-management-alpine | — | 5672, 15672 |

### Manifest Structure

```
kubernetes/
├── alb-controller/
│   └── iam_policy.json              # ALB controller IAM policy (referenced by irsa.tf)
└── manifests/
    ├── base/
    │   ├── namespace.yaml           # retail-app namespace
    │   └── serviceaccounts.yaml     # external-secrets-sa and carts-sa (with IRSA annotations)
    ├── apps/
    │   ├── assets.yaml
    │   ├── carts.yaml
    │   ├── catalog.yaml
    │   ├── checkout.yaml
    │   ├── orders.yaml
    │   ├── rabbitmq.yaml
    │   ├── redis.yaml
    │   └── ui.yaml
    ├── autoscaling/
    │   └── ui-hpa.yaml              # HPA for ui (1–3 replicas, 70% CPU)
    ├── ingress/
    │   └── retail-ingress.yaml      # ALB ingress, internet-facing
    └── secrets/
        ├── secretstore.yaml         # Namespace-scoped SecretStore (retail-app)
        ├── mysql-external-secret.yaml     # Syncs mysql-secret from Secrets Manager
        ├── postgres-external-secret.yaml  # Syncs catalog-db-secret from Secrets Manager
        ├── external-secrets-policy.json   # IAM policy document (applied via irsa.tf)
        └── external-secrets-trust-policy.json  # Reference trust policy
```

### Ingress

Traffic enters through an internet-facing AWS ALB, provisioned automatically by the AWS Load Balancer Controller when the Ingress manifest is applied. All HTTP traffic on port 80 routes to the `ui` service.

### Horizontal Pod Autoscaler

The `ui` deployment is configured with an HPA that scales between 1 and 3 replicas based on CPU utilisation (target: 70%).

---

## Security Design

### IAM Roles for Service Accounts (IRSA)

No static AWS credentials are used anywhere. Each service that needs AWS access has a dedicated Kubernetes service account bound to an IAM role via OIDC federation. All IRSA roles are created by Terraform in `irsa.tf` and reference `module.eks.oidc_provider_arn` — no manual IAM setup required.

| Service Account | Namespace | IAM Role | Permissions |
|---|---|---|---|
| `aws-load-balancer-controller` | kube-system | `project-bedrock-alb-controller-role` | ELB, EC2 management |
| `external-secrets-sa` | retail-app | `project-bedrock-external-secrets-role` | Secrets Manager read |
| `carts-sa` | retail-app | `project-bedrock-carts-role` | DynamoDB read/write on products table |

### Secrets Pipeline

Database credentials are never stored in Kubernetes manifests or environment variables directly. The flow for MySQL credentials is:

```
AWS Secrets Manager (RDS-managed, auto-generated)
        ↓
External Secrets Operator (syncs every 1 hour)
        ↓
Kubernetes Secrets (mysql-secret in retail-app)
        ↓
Application pods (injected as environment variables)
```

The `catalog` service uses a dedicated `catalog-mysql-creds` Kubernetes Secret (created during setup) holding the `catalog_app` MySQL user credentials. This user has narrowly scoped permissions on the `catalog` database only.

### Network Security

- EKS nodes and RDS instances run in **private subnets** with no direct internet access
- RDS security group allows inbound MySQL (3306) and PostgreSQL (5432) **only from the EKS node security group**
- Public internet reaches the application exclusively through the ALB
- NAT gateway provides outbound internet access for nodes (pulling images, AWS API calls)

### Data Encryption

- All RDS instances have `storage_encrypted = true`
- EKS cluster secrets are encrypted with a KMS key provisioned by the EKS Terraform module
- Secrets Manager secrets are encrypted at rest by AWS-managed KMS keys

### Snapshot Protection

Both RDS instances are configured with:
- `skip_final_snapshot = false` — a final snapshot is taken before any destroy
- `final_snapshot_identifier` set per instance so data can be recovered

---

## CI/CD Pipeline

Two GitHub Actions workflows validate changes on push and pull request.

### Terraform Validation (`.github/workflows/terraform.yml`)

Triggers on changes to `terraform/**`.

| Step | Action |
|---|---|
| Checkout | `actions/checkout@v4` |
| Setup Terraform | `hashicorp/setup-terraform@v3` |
| `terraform init` | Initialises without backend (validation only) |
| `terraform fmt -check` | Enforces canonical formatting |
| `terraform validate` | Validates HCL syntax and provider schema |

### Kubernetes Manifest Validation (`.github/workflows/kubernetes.yml`)

Triggers on changes to `kubernetes/**`.

| Step | Action |
|---|---|
| Checkout | `actions/checkout@v4` |
| Install kubectl | `azure/setup-kubectl@v4` |
| Dry-run validation | `kubectl apply --dry-run=client` on all YAML files |

---

## Observability

### EKS Control Plane Logs

All five EKS control plane log types are enabled and ship to CloudWatch Logs under `/aws/eks/project-bedrock-cluster/cluster`:

- `api` — Kubernetes API server
- `audit` — API audit trail
- `authenticator` — IAM authentication
- `controllerManager` — controller reconciliation
- `scheduler` — pod scheduling decisions

### Application Observability

At the cluster level, `kubectl logs`, `kubectl describe`, and `kubectl top` provide runtime visibility. The RabbitMQ management UI is available at port 15672 on the `rabbitmq` service for queue inspection.

---

## Startup — Full Deployment

### Prerequisites

Ensure the following tools are installed and configured before starting:

- AWS CLI — authenticated with sufficient IAM permissions (`AdministratorAccess` or equivalent)
- Terraform >= 1.5
- kubectl
- helm

---

### Step 1 — Create the Terraform State Bucket

This is a one-time step. Skip if the bucket already exists.

```bash
aws s3api create-bucket \
  --bucket project-bedrock-tfstate-3152 \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket project-bedrock-tfstate-3152 \
  --versioning-configuration Status=Enabled
```

---

### Step 2 — Provision AWS Infrastructure

This creates the VPC, EKS cluster, RDS instances, DynamoDB table, and all IRSA IAM roles.

```bash
cd terraform
terraform init
terraform apply
cd ..
```

---

### Step 3 — Configure kubectl

```bash
aws eks update-kubeconfig \
  --name project-bedrock-cluster \
  --region us-east-1
```

Verify the connection:

```bash
kubectl get nodes
```

---

### Step 4 — Install AWS Load Balancer Controller

The IAM role was already created by Terraform. Fetch its ARN and install via Helm.

```bash
ALB_ROLE_ARN=$(cd terraform && terraform output -raw alb_controller_role_arn)

helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=project-bedrock-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${ALB_ROLE_ARN}"
```

---

### Step 5 — Install External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --create-namespace
```

---

### Step 6 — Deploy Kubernetes Base Resources

Apply the namespace and service accounts (IRSA annotations are already set).

```bash
kubectl apply -f kubernetes/manifests/base/
```

---

### Step 7 — Apply Secrets and Wait for Sync

```bash
kubectl apply -f kubernetes/manifests/secrets/secretstore.yaml
kubectl apply -f kubernetes/manifests/secrets/mysql-external-secret.yaml
kubectl apply -f kubernetes/manifests/secrets/postgres-external-secret.yaml

# Wait for mysql-secret to be populated before continuing
kubectl wait externalsecret mysql-secret \
  -n retail-app \
  --for=condition=Ready \
  --timeout=120s
```

---

### Step 8 — Prepare the Catalog MySQL Database

The catalog service runs as a dedicated `catalog_app` database user. This step creates the `catalog` database and the application user on the MySQL RDS instance.

```bash
MYSQL_HOST=$(kubectl get secret mysql-secret -n retail-app \
  -o jsonpath='{.data.host}' | base64 -d)
MYSQL_USER=$(kubectl get secret mysql-secret -n retail-app \
  -o jsonpath='{.data.username}' | base64 -d)
MYSQL_PASS=$(kubectl get secret mysql-secret -n retail-app \
  -o jsonpath='{.data.password}' | base64 -d)

kubectl run mysql-setup --image=mysql:8.0 --restart=Never -n retail-app \
  --env="H=$MYSQL_HOST" --env="U=$MYSQL_USER" --env="P=$MYSQL_PASS" \
  --command -- sh -c 'mysql -h "$H" -u "$U" -p"$P" -e "
    CREATE DATABASE IF NOT EXISTS catalog;
    CREATE USER IF NOT EXISTS '"'"'catalog_app'"'"'@'"'"'%'"'"'
      IDENTIFIED WITH mysql_native_password BY '"'"'CatalogApp2026x'"'"';
    GRANT ALL PRIVILEGES ON catalog.* TO '"'"'catalog_app'"'"'@'"'"'%'"'"';
    FLUSH PRIVILEGES;"'

kubectl wait pod/mysql-setup -n retail-app \
  --for=condition=Ready --timeout=60s 2>/dev/null || true
kubectl logs mysql-setup -n retail-app
kubectl delete pod mysql-setup -n retail-app
```

Then store the catalog credentials as a Kubernetes Secret:

```bash
kubectl create secret generic catalog-mysql-creds -n retail-app \
  --from-literal=username=catalog_app \
  --from-literal=password=CatalogApp2026x \
  --from-literal=host="$(kubectl get secret mysql-secret -n retail-app \
    -o jsonpath='{.data.host}' | base64 -d)"
```

---

### Step 9 — Deploy Application Services

```bash
kubectl apply -f kubernetes/manifests/apps/
```

---

### Step 10 — Apply Ingress and Autoscaling

```bash
kubectl apply -f kubernetes/manifests/ingress/
kubectl apply -f kubernetes/manifests/autoscaling/
```

---

### Step 11 — Verify All Pods Are Running

```bash
kubectl get pods -n retail-app
```

All eight pods should show `1/1 Running`:

```
NAME                      READY   STATUS    RESTARTS   AGE
assets-...                1/1     Running   0          ...
carts-...                 1/1     Running   0          ...
catalog-...               1/1     Running   0          ...
checkout-...              1/1     Running   0          ...
orders-...                1/1     Running   0          ...
rabbitmq-...              1/1     Running   0          ...
redis-...                 1/1     Running   0          ...
ui-...                    1/1     Running   0          ...
```

---

### Step 12 — Get the Application URL

```bash
kubectl get ingress retail-ingress -n retail-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

The ALB takes approximately 2 minutes to become active after the Ingress is applied. Open `http://<ALB_HOSTNAME>/home` in a browser once the ADDRESS field is populated.

---

## Shutdown — Teardown

### Step 1 — Delete Application Workloads

```bash
kubectl delete -f kubernetes/manifests/autoscaling/
kubectl delete -f kubernetes/manifests/ingress/
kubectl delete -f kubernetes/manifests/apps/
kubectl delete secret catalog-mysql-creds -n retail-app
kubectl delete -f kubernetes/manifests/secrets/postgres-external-secret.yaml
kubectl delete -f kubernetes/manifests/secrets/mysql-external-secret.yaml
kubectl delete -f kubernetes/manifests/secrets/secretstore.yaml
kubectl delete -f kubernetes/manifests/base/
```

### Step 2 — Uninstall Helm Releases

```bash
helm uninstall aws-load-balancer-controller -n kube-system
helm uninstall external-secrets -n external-secrets
kubectl delete namespace external-secrets
```

### Step 3 — Destroy AWS Infrastructure

```bash
cd terraform
terraform destroy
cd ..
```

> **Note:** Both RDS instances will create final snapshots named `project-bedrock-mysql-final` and `project-bedrock-postgres-final` before deletion. Delete these manually from the RDS console if they are no longer needed to avoid ongoing snapshot storage costs.

---

## Screenshots

> Add screenshots of the deployed application here.

- `[ ]` Home page loaded via ALB DNS
- `[ ]` Product catalog listing
- `[ ]` Shopping cart flow
- `[ ]` Checkout page
- `[ ]` `kubectl get pods -n retail-app` showing all Running
- `[ ]` AWS Console — EKS cluster
- `[ ]` AWS Console — RDS instances
- `[ ]` AWS Console — Secrets Manager secrets
- `[ ]` GitHub Actions — passing Terraform and Kubernetes workflows

---

## Cost Optimisation Decisions

Several deliberate trade-offs were made to keep the project cost-conscious while still demonstrating production patterns.

| Decision | Reason |
|---|---|
| `t3.small` EC2 nodes | Provides more pod capacity than `t3.micro` while keeping the EKS worker nodes small and inexpensive |
| Single NAT gateway | Eliminates the cost of one NAT gateway per AZ; acceptable single point of failure for a non-production deployment |
| `PAY_PER_REQUEST` DynamoDB | No provisioned capacity cost when the table is idle |
| `db.t3.micro` RDS instances | Smallest available RDS instance; sufficient for a capstone workload |
| 4-node desired capacity | Matches the Terraform managed node group configuration while leaving room to scale between 2 and 5 nodes |
| `gp3` storage on RDS | 20% cheaper than `gp2` with better baseline performance |
| Single-replica deployments | Conserves pod slots across the small managed node group |

---

## Challenges and Solutions

### 1. Worker Node Pod Capacity

**Challenge:** AWS VPC CNI limits pods per node based on instance networking capacity. An earlier `t3.micro` worker-node design left too few schedulable pod slots once kube-system workloads were running.

**Solution:** Updated the Terraform-managed node group to use `t3.small` instances with a desired size of 4, minimum size of 2, and maximum size of 5. This gives the cluster more practical pod capacity while keeping the deployment small.

### 2. Hardcoded Database Passwords

**Challenge:** The initial Terraform config had plaintext passwords in `data-layer.tf`.

**Solution:** Replaced with `manage_master_user_password = true` on both RDS instances. AWS now generates and stores the master password in Secrets Manager. External Secrets Operator syncs the credentials into Kubernetes secrets automatically.

### 3. Catalog Service Password Corruption

**Challenge:** The catalog service Go binary uses the Viper configuration library, which performs environment variable expansion on config values at startup. The AWS-generated RDS master password contained `$` characters (e.g. `$beE0psHIbuGB~8Ks`). Viper treated `$beE0psHIbuGB` as a shell variable reference, expanded it to an empty string, and sent a corrupted password to MySQL — resulting in persistent `Access denied` errors even though the credentials in the Kubernetes secret were correct.

**Solution:** Created a dedicated `catalog_app` MySQL user with the `mysql_native_password` plugin and a simple alphanumeric password containing no `$` or shell-special characters. This user is granted permissions only on the `catalog` database. Its credentials are stored in a `catalog-mysql-creds` Kubernetes secret and injected into the catalog pod directly, bypassing the Viper expansion issue and following least-privilege access.

### 4. Orders Service JDBC Driver Conflict

**Challenge:** Setting `SPRING_DATASOURCE_URL=jdbc:mariadb://...` caused a `ClassNotFoundException` for `org.mariadb.jdbc.Driver`. Switching to `jdbc:mysql://...` caused the same error for `com.mysql.cj.jdbc.Driver`. Neither driver was discoverable by the HikariCP classloader, even though the orders Spring Boot image had previously started successfully.

**Solution:** The orders image bundles its own internal datasource URL in `application.properties` that references the correct, bundled driver. Overriding `SPRING_DATASOURCE_URL` with any scheme forced Spring Boot to look for a driver that was not in the classpath. Removing the `SPRING_DATASOURCE_URL` env var entirely — while retaining `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`, and `DB_HOST` — lets the image use its own default URL and resolves the issue.

### 5. Stale RDS Secret IDs After Re-deployment

**Challenge:** After tearing down and re-provisioning the infrastructure, the ExternalSecret manifests still referenced the old Secrets Manager secret keys from the previous deployment (e.g. `rds!db-62916505-...`). The new RDS instances generate new secret IDs. The ExternalSecrets entered `SecretSyncedError` and the app pods could not start.

**Solution:** After each `terraform apply`, retrieve the new secret ARNs from Terraform outputs and update `mysql-external-secret.yaml` and `postgres-external-secret.yaml` with the correct keys. The grading outputs are saved to `terraform/grading.json` for reference.

### 6. IRSA Not Wired for ALB Controller, External Secrets, or Carts

**Challenge:** The initial configuration had IAM policy JSON files but no Terraform resources to create the IRSA roles, and no Kubernetes ServiceAccount manifests with the correct annotations.

**Solution:** Added `terraform/irsa.tf` to create all three IRSA roles (ALB controller, External Secrets, carts) dynamically using `module.eks.oidc_provider_arn` and `module.eks.cluster_oidc_issuer_url`. Added `kubernetes/manifests/base/serviceaccounts.yaml` with the IRSA role ARN annotations pre-populated.

---

## Stack Summary

| Category | Technology |
|---|---|
| Cloud | AWS (us-east-1) |
| IaC | Terraform >= 1.5 |
| Container Orchestration | Amazon EKS 1.33 |
| Secret Management | AWS Secrets Manager + External Secrets Operator |
| Identity | IRSA (IAM Roles for Service Accounts) — all managed by Terraform |
| Ingress | AWS ALB via Load Balancer Controller |
| Databases | RDS MySQL 8.0 (orders + catalog), RDS PostgreSQL 17 (provisioned), DynamoDB |
| Messaging | RabbitMQ 3 |
| Caching | Redis 7 |
| CI/CD | GitHub Actions |
| Application | AWS Retail Store Sample App v0.8.5 |
