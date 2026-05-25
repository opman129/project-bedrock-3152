# Project Bedrock — AltSchool Karatu 2025 Capstone

Production-grade AWS EKS deployment of the [AWS Retail Store Sample App](https://github.com/aws-containers/retail-store-sample-app), built as a capstone project for AltSchool Africa's Karatu 2025 cohort.

---

## Project Overview

Project Bedrock provisions and deploys a fully operational cloud-native e-commerce platform on AWS. The application is a microservices-based retail store with a frontend, product catalog, shopping cart, checkout flow, and order management — all running on Kubernetes with managed databases, automated secret synchronisation, and infrastructure-as-code.

The goal is to demonstrate production patterns that go far beyond a basic Kubernetes deployment:

- Infrastructure provisioned entirely with Terraform
- Secrets managed through AWS Secrets Manager and synchronised into Kubernetes automatically via External Secrets Operator
- IAM roles bound to Kubernetes service accounts (IRSA) — no static credentials
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
                          │  ┌──────────┐  ┌───────────────────┐   │
                          │  │ RDS MySQL│  │  RDS PostgreSQL    │   │
                          │  │ (orders) │  │  (retailcatalog)   │   │
                          │  └──────────┘  └───────────────────┘   │
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
| Compute Nodes | EC2 t3.micro | 8 nodes, ON_DEMAND capacity |
| Networking | VPC + Subnets + NAT | 2 AZs, public + private subnets |
| Relational DB (orders) | RDS MySQL 8.0 | db.t3.micro, 20GB gp3, encrypted |
| Relational DB (catalog) | RDS PostgreSQL 17 | db.t3.micro, 20GB gp3, encrypted |
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
└── outputs.tf        # Cluster endpoint, DB endpoints, secret ARNs
```

---

## Kubernetes Architecture

All application workloads run in the `retail-app` namespace.

### Microservices

| Service | Image | Backend | Port |
|---|---|---|---|
| `ui` | retail-store-sample-ui:0.8.5 | — | 8080 |
| `catalog` | retail-store-sample-catalog:0.8.5 | RDS MySQL | 8080 |
| `carts` | retail-store-sample-cart:0.8.5 | DynamoDB + Redis | 8080 |
| `orders` | retail-store-sample-orders:0.8.5 | RDS MySQL | 8080 |
| `checkout` | retail-store-sample-checkout:0.8.5 | Redis | 8080 |
| `assets` | retail-store-sample-assets:0.8.5 | — | 8080 |
| `redis` | redis:7-alpine | — | 6379 |
| `rabbitmq` | rabbitmq:3-management-alpine | — | 5672, 15672 |

### Manifest Structure

```
kubernetes/
├── alb-controller/
│   └── iam_policy.json              # ALB controller IAM policy
└── manifests/
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
        ├── secretstore.yaml         # Namespace-scoped SecretStore
        ├── mysql-external-secret.yaml
        ├── postgres-external-secret.yaml
        ├── external-secrets-policy.json
        └── external-secrets-trust-policy.json
```

### Ingress

Traffic enters through an internet-facing AWS ALB, provisioned automatically by the AWS Load Balancer Controller when the Ingress manifest is applied. All HTTP traffic on port 80 routes to the `ui` service.

### Horizontal Pod Autoscaler

The `ui` deployment is configured with an HPA that scales between 1 and 3 replicas based on CPU utilisation (target: 70%).

---

## Security Design

### IAM Roles for Service Accounts (IRSA)

No static AWS credentials are used anywhere. Each service that needs AWS access has a dedicated Kubernetes service account bound to an IAM role via OIDC federation.

| Service Account | Namespace | IAM Role | Permissions |
|---|---|---|---|
| `aws-load-balancer-controller` | kube-system | ALB Controller Role | ELB, EC2 management |
| `external-secrets` | external-secrets | ExternalSecretsRole | Secrets Manager read |
| `external-secrets-sa` | retail-app | RetailAppSecretsRole | Secrets Manager read |
| `carts-sa` | retail-app | CartsRole | DynamoDB read/write on products table |

### Secrets Pipeline

Database credentials are never stored in Kubernetes manifests or environment variables directly. The full flow is:

```
AWS Secrets Manager (RDS-managed, auto-rotated)
        ↓
External Secrets Operator (syncs every 1 hour)
        ↓
Kubernetes Secret (mysql-secret, postgres-secret in retail-app)
        ↓
Application pods (injected as environment variables)
```

RDS instances use `manage_master_user_password = true`, meaning AWS generates and rotates the master password automatically. Applications read the current credentials from Kubernetes secrets that stay synchronised with Secrets Manager via External Secrets Operator.

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

## Deployment Instructions

### Prerequisites

- AWS CLI configured with appropriate IAM permissions
- Terraform >= 1.5
- kubectl
- helm
- eksctl

### 1. Provision Infrastructure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

### 2. Configure kubectl

```bash
aws eks update-kubeconfig \
  --name project-bedrock-cluster \
  --region us-east-1
```

### 3. Install AWS Load Balancer Controller

```bash
# Create IAM policy
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://kubernetes/alb-controller/iam_policy.json

# Create IRSA service account
eksctl create iamserviceaccount \
  --cluster=project-bedrock-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name=AWSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve \
  --region=us-east-1

# Install via Helm
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=project-bedrock-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### 4. Install External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --create-namespace
```

### 5. Set Up IRSA for External Secrets

```bash
# Create IAM policy
aws iam create-policy \
  --policy-name ExternalSecretsPolicy \
  --policy-document file://kubernetes/manifests/secrets/external-secrets-policy.json

# Create IRSA role for external-secrets namespace
aws iam create-role \
  --role-name ExternalSecretsRole \
  --assume-role-policy-document file://kubernetes/manifests/secrets/external-secrets-trust-policy.json

aws iam attach-role-policy \
  --role-name ExternalSecretsRole \
  --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/ExternalSecretsPolicy

kubectl annotate serviceaccount external-secrets \
  -n external-secrets \
  eks.amazonaws.com/role-arn=arn:aws:iam::<ACCOUNT_ID>:role/ExternalSecretsRole

kubectl rollout restart deployment external-secrets -n external-secrets
```

### 6. Set Up retail-app Namespace and Secrets

```bash
kubectl create namespace retail-app

# IRSA for retail-app secrets access
eksctl create iamserviceaccount \
  --cluster=project-bedrock-cluster \
  --namespace=retail-app \
  --name=external-secrets-sa \
  --role-name=RetailAppSecretsRole \
  --attach-policy-arn=arn:aws:iam::<ACCOUNT_ID>:policy/ExternalSecretsPolicy \
  --approve \
  --region=us-east-1

# IRSA for carts DynamoDB access
aws iam create-policy \
  --policy-name CartsDynamoDBPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["dynamodb:GetItem","dynamodb:PutItem","dynamodb:UpdateItem",
                 "dynamodb:DeleteItem","dynamodb:Query","dynamodb:Scan"],
      "Resource": "arn:aws:dynamodb:us-east-1:<ACCOUNT_ID>:table/project-bedrock-products"
    }]
  }'

eksctl create iamserviceaccount \
  --cluster=project-bedrock-cluster \
  --namespace=retail-app \
  --name=carts-sa \
  --role-name=CartsDynamoDBRole \
  --attach-policy-arn=arn:aws:iam::<ACCOUNT_ID>:policy/CartsDynamoDBPolicy \
  --approve \
  --region=us-east-1

# Apply SecretStore and ExternalSecrets
kubectl apply -f kubernetes/manifests/secrets/secretstore.yaml
kubectl apply -f kubernetes/manifests/secrets/mysql-external-secret.yaml
kubectl apply -f kubernetes/manifests/secrets/postgres-external-secret.yaml
```

### 7. Deploy Application Services

```bash
kubectl apply -f kubernetes/manifests/apps/redis.yaml
kubectl apply -f kubernetes/manifests/apps/rabbitmq.yaml
kubectl apply -f kubernetes/manifests/apps/catalog.yaml
kubectl apply -f kubernetes/manifests/apps/carts.yaml
kubectl apply -f kubernetes/manifests/apps/orders.yaml
kubectl apply -f kubernetes/manifests/apps/checkout.yaml
kubectl apply -f kubernetes/manifests/apps/assets.yaml
kubectl apply -f kubernetes/manifests/apps/ui.yaml
```

### 8. Apply Ingress and Autoscaling

```bash
kubectl apply -f kubernetes/manifests/ingress/retail-ingress.yaml
kubectl apply -f kubernetes/manifests/autoscaling/ui-hpa.yaml
```

### 9. Get the Application URL

```bash
kubectl get ingress retail-ingress -n retail-app
```

The `ADDRESS` field contains the ALB DNS name. The application is available at `http://<ALB_DNS>`.

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

Several deliberate trade-offs were made to keep the project within AWS Free Tier and minimise cost while still demonstrating production patterns.

| Decision | Reason |
|---|---|
| `t3.micro` EC2 nodes | Free Tier eligible; the only instance type permitted in this account |
| Single NAT gateway | Eliminates the cost of one NAT gateway per AZ; acceptable single point of failure for a non-production deployment |
| `PAY_PER_REQUEST` DynamoDB | No provisioned capacity cost when the table is idle |
| `db.t3.micro` RDS instances | Smallest available RDS instance; sufficient for a capstone workload |
| 8 nodes instead of larger instances | Free Tier allows t3.micro only; horizontal scaling compensates for the 4-pod-per-node limit imposed by VPC CNI |
| `gp3` storage on RDS | 20% cheaper than `gp2` with better baseline performance |
| Single-replica deployments | Conserves pod slots across 8 t3.micro nodes (32 total slots) |

---

## Challenges and Solutions

### 1. t3.micro Pod Limit (4 pods per node)

**Challenge:** AWS VPC CNI limits pods per node based on ENI count. `t3.micro` supports only 4 pods per node. With kube-system pods already consuming slots, application pods could not be scheduled.

**Solution:** Scaled the node group horizontally to 8 nodes, giving 32 total pod slots. Used `aws eks update-nodegroup-config` directly since the Terraform EKS module ignores `desired_size` changes (to avoid conflicts with cluster autoscaler).

### 2. Hardcoded Database Passwords

**Challenge:** The initial Terraform config had plaintext passwords in `data-layer.tf`.

**Solution:** Replaced with `manage_master_user_password = true` on both RDS instances. AWS now generates, stores, and rotates the master password in Secrets Manager. External Secrets Operator syncs the credentials into Kubernetes secrets automatically.

### 3. MySQL Authentication Plugin Incompatibility

**Challenge:** MySQL 8.0 on RDS defaults to `caching_sha2_password`. The catalog service's Go MySQL driver did not support this plugin, resulting in "Access Denied" errors despite correct credentials.

**Solution:** Created a dedicated `catalog_app` database user with `mysql_native_password` authentication plugin and stored the credentials in a Kubernetes secret. This also follows the principle of least privilege — the catalog service no longer uses the admin account.

### 4. Orders Service JDBC Driver Mismatch

**Challenge:** The orders Spring Boot image bundles the MariaDB JDBC driver, not MySQL Connector/J. Setting `SPRING_DATASOURCE_URL=jdbc:mysql://...` caused a `ClassNotFoundException` for `com.mysql.cj.jdbc.Driver`.

**Solution:** Changed the JDBC URL prefix to `jdbc:mariadb://`. The MariaDB connector is fully compatible with MySQL 8.0 and correctly initialises the Spring Data JDBC context.

### 5. External Secrets API Version Mismatch

**Challenge:** Manifests written for `external-secrets.io/v1beta1` failed to apply because the installed version of External Secrets Operator serves resources under `external-secrets.io/v1`.

**Solution:** Updated all ExternalSecret, SecretStore, and ClusterSecretStore manifests to use `apiVersion: external-secrets.io/v1`.

### 6. RDS-Managed Secret Fields

**Challenge:** The ExternalSecret manifests attempted to pull `host` and `dbname` fields from the RDS-managed Secrets Manager secret. RDS native password management only stores `username` and `password`.

**Solution:** Used ExternalSecret's `spec.target.template` to inject static connection details (host, dbname, port) alongside the dynamically fetched credentials, producing a complete connection secret from a single ExternalSecret resource.

---

## Cleanup Instructions

### Destroy Kubernetes Resources

```bash
kubectl delete -f kubernetes/manifests/ingress/
kubectl delete -f kubernetes/manifests/autoscaling/
kubectl delete -f kubernetes/manifests/apps/
kubectl delete -f kubernetes/manifests/secrets/
kubectl delete namespace retail-app
kubectl delete namespace external-secrets
```

### Remove Helm Releases

```bash
helm uninstall aws-load-balancer-controller -n kube-system
helm uninstall external-secrets -n external-secrets
```

### Remove IRSA Resources

```bash
eksctl delete iamserviceaccount --cluster=project-bedrock-cluster --namespace=retail-app --name=external-secrets-sa --region=us-east-1
eksctl delete iamserviceaccount --cluster=project-bedrock-cluster --namespace=retail-app --name=carts-sa --region=us-east-1
eksctl delete iamserviceaccount --cluster=project-bedrock-cluster --namespace=kube-system --name=aws-load-balancer-controller --region=us-east-1

aws iam delete-policy --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/ExternalSecretsPolicy
aws iam delete-policy --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/CartsDynamoDBPolicy
aws iam delete-policy --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy
```

### Destroy Infrastructure

```bash
cd terraform
terraform destroy
```

> **Note:** Both RDS instances will create final snapshots named `project-bedrock-mysql-final` and `project-bedrock-postgres-final` before deletion. Delete these manually from the RDS console if they are no longer needed to avoid ongoing snapshot storage costs.

---

## Stack Summary

| Category | Technology |
|---|---|
| Cloud | AWS (us-east-1) |
| IaC | Terraform >= 1.5 |
| Container Orchestration | Amazon EKS 1.33 |
| Secret Management | AWS Secrets Manager + External Secrets Operator |
| Identity | IRSA (IAM Roles for Service Accounts) |
| Ingress | AWS ALB via Load Balancer Controller |
| Databases | RDS MySQL 8.0, RDS PostgreSQL 17, DynamoDB |
| Messaging | RabbitMQ 3 |
| Caching | Redis 7 |
| CI/CD | GitHub Actions |
| Application | AWS Retail Store Sample App v0.8.5 |
