# DevOps Case Study — MERN + Python ETL on AWS EKS

End-to-end deployment of a 3-tier MERN application (React + Express + MongoDB)
and a Python ETL job to AWS EKS. Containerized with Docker, provisioned with
Terraform, orchestrated by Kubernetes, shipped by GitHub Actions, and observed
via CloudWatch Logs / Alarms.

![result](result.png "Result")

---

## Acceptance criteria (from the original brief)

**MERN app**
1. MongoDB should be connected ✅
2. All endpoints should work ✅
3. All pages should work ✅

**Python project**
1. `ETL.py` should run every 1 hour ✅ — Kubernetes `CronJob`, schedule `0 * * * *`

---

## Architecture

```
                            ┌────────────────────────────┐
   Internet ──── HTTP ────► │  AWS Application LB (ALB)  │
                            │  (provisioned by Ingress)  │
                            └─────────────┬──────────────┘
                                          │
                                ┌─────────▼──────────┐
                                │  frontend (nginx)  │  Deployment, replicas: 2
                                │  serves React +    │  HPA: cpu 70%, max 5
                                │  proxies /record   │
                                │  & /healthcheck    │
                                └─────────┬──────────┘
                                          │ ClusterIP
                                ┌─────────▼──────────┐
                                │  backend (Express) │  Deployment, replicas: 2
                                │  port 5050         │  HPA: cpu 70%, max 6
                                └─────────┬──────────┘
                                          │ ClusterIP (headless)
                                ┌─────────▼──────────┐
                                │  mongodb (StatefulSet) │  PVC 10Gi gp3 EBS
                                │  port 27017            │  authn enabled
                                └────────────────────┘

   ┌──────────────────────────────────────────────────────────────┐
   │  CronJob "etl"  ──► spawns Python pod every hour (UTC)       │
   │                     calls api.github.com, prints response    │
   └──────────────────────────────────────────────────────────────┘

   ┌──────────────────────────────────────────────────────────────┐
   │  fluent-bit DaemonSet (every node) ──► CloudWatch Logs       │
   │                                          /aws/eks/<cluster>/ │
   │                                            application       │
   │                                            host              │
   │                                          ──► metric filter   │
   │                                          ──► CloudWatch      │
   │                                              Alarm ──► SNS   │
   │                                                       ──► email │
   └──────────────────────────────────────────────────────────────┘

   AWS account
   ├─ VPC 10.20.0.0/16  (3 AZs, public + private subnets, 1 NAT GW)
   ├─ EKS cluster (workers in PRIVATE subnets)
   ├─ ECR repos: <prefix>/frontend, <prefix>/backend, <prefix>/etl
   └─ IAM/IRSA: EBS CSI, AWS LB Controller, Fluent Bit
```

The frontend's nginx is the API gateway: React calls relative paths
(`/record/`, `/healthcheck/`) and nginx proxies them to the `backend`
Service over the cluster network. This keeps the React build environment
agnostic and removes the need for CORS at the edge.

---

## Repository layout

```
DevOps-Case-Study/
├── mern-project/
│   ├── client/                # React (CRA) + Dockerfile (multi-stage Node→nginx) + nginx.conf
│   └── server/                # Express + Dockerfile (Node 18, tini, non-root)
├── python-project/            # ETL.py + Dockerfile (python:3.11-slim) + requirements.txt
├── docker-compose.yml         # Local-only smoke test stack
├── terraform/                 # AWS infra: VPC, EKS, ECR, observability, IRSA
├── k8s/                       # Cluster manifests
│   ├── 00-namespace.yaml
│   ├── 10-mongodb-secret.yaml
│   ├── 11-mongodb-statefulset.yaml
│   ├── 20-backend.yaml
│   ├── 30-frontend.yaml
│   ├── 40-ingress.yaml
│   ├── 50-etl-cronjob.yaml
│   ├── 60-networkpolicies.yaml
│   ├── 61-pdb.yaml
│   └── logging/               # Fluent Bit DaemonSet → CloudWatch
└── .github/workflows/
    ├── ci.yml                 # PR validation: build, lint, docker smoke
    ├── deploy.yml             # Build → ECR → kubectl apply
    └── terraform.yml          # fmt / validate / plan / apply
```

---

## Prerequisites

| Tool         | Version  | Purpose                            |
|--------------|----------|------------------------------------|
| Docker       | ≥ 24     | Build images, run docker-compose   |
| AWS CLI      | ≥ 2.15   | Auth + `update-kubeconfig`         |
| Terraform    | ≥ 1.5    | Provision AWS infra                |
| kubectl      | ≥ 1.30   | Cluster ops                        |
| helm         | ≥ 3.13   | Install AWS Load Balancer Controller |

AWS prerequisites:
- An AWS account with permissions to create VPC, EKS, IAM, and ECR resources
- (Recommended) An S3 bucket + DynamoDB table for Terraform remote state
- A GitHub OIDC IAM role (`AWS_DEPLOY_ROLE_ARN`) trusted by your repo

---

## Quickstart — local with docker-compose

This proves the wiring before touching AWS.

```bash
docker compose up --build
# open http://localhost:8080
#   "/" → API status (calls /healthcheck through nginx → backend)
#   "/records" → record list (calls /record/)
#   "/create" → POST a new record
```

Stop with `Ctrl+C`; data persists in the `mongo-data` volume. To wipe:
`docker compose down -v`.

To exercise the ETL container locally:
```bash
docker compose --profile etl up etl
```

---

## Provisioning AWS — Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit aws_region, project, alert_email…

terraform init
terraform plan -out tfplan
terraform apply tfplan
```

Apply takes ~15 min (EKS control plane is the long pole). Outputs include:

```
cluster_name              = "mern-devops-dev-eks"
ecr_repository_urls       = { backend = "...", frontend = "...", etl = "..." }
alb_controller_role_arn   = "arn:aws:iam::...:role/mern-devops-dev-alb-controller"
fluentbit_role_arn        = "arn:aws:iam::...:role/mern-devops-dev-fluentbit"
kubeconfig_command        = "aws eks update-kubeconfig --region ... --name ..."
```

Wire up your local kubeconfig:
```bash
$(terraform output -raw kubeconfig_command)
kubectl get nodes
```

### Install the AWS Load Balancer Controller (once per cluster)

The Ingress in `k8s/40-ingress.yaml` is consumed by this controller.

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

CLUSTER=$(terraform -chdir=terraform output -raw cluster_name)
ROLE_ARN=$(terraform -chdir=terraform output -raw alb_controller_role_arn)
REGION=$(terraform -chdir=terraform output -raw cluster_endpoint | sed 's/.*\.\(.*\)\.eks.*/\1/')
VPC_ID=$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
          --query 'cluster.resourcesVpcConfig.vpcId' --output text)

kubectl create serviceaccount aws-load-balancer-controller -n kube-system --dry-run=client -o yaml \
  | kubectl apply -f -
kubectl annotate sa aws-load-balancer-controller -n kube-system \
  eks.amazonaws.com/role-arn=$ROLE_ARN --overwrite

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER \
  --set region=$REGION \
  --set vpcId=$VPC_ID \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### Install Fluent Bit

```bash
ROLE_ARN=$(terraform -chdir=terraform output -raw fluentbit_role_arn)

# Patch the ServiceAccount annotation to your IRSA role
sed -i.bak "s|arn:aws:iam::ACCOUNT_ID:role/mern-devops-dev-fluentbit|$ROLE_ARN|" \
  k8s/logging/10-serviceaccount.yaml

kubectl apply -f k8s/logging/
kubectl -n amazon-cloudwatch rollout status ds/fluent-bit --timeout=2m
```

---

## Deploying the application

### From CI (recommended)

Push to `main`. The `Deploy` workflow (`.github/workflows/deploy.yml`):
1. Assumes `AWS_DEPLOY_ROLE_ARN` via OIDC
2. Builds the three images, pushes them to ECR (immutable tag = git short SHA)
3. Substitutes the image tags into the K8s manifests
4. `kubectl apply` and waits for `rollout status` on backend, frontend, mongodb
5. Resolves the ALB hostname and prints it

Required GitHub repo configuration:

| Type    | Name                  | Example value                                      |
|---------|-----------------------|----------------------------------------------------|
| Secret  | `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::123456789012:role/github-deploy`     |
| Variable| `AWS_REGION`          | `eu-central-1`                                     |
| Variable| `EKS_CLUSTER_NAME`    | `mern-devops-dev-eks`                              |
| Variable| `ECR_PREFIX`          | `mern-devops-dev`                                  |

### Manual one-off deploy

```bash
cd k8s
REG=$(aws ecr describe-registry --query registryId --output text).dkr.ecr.eu-central-1.amazonaws.com
TAG=manual-$(date +%s)

# (build & push images yourself, or grab an existing tag)
kubectl apply -f 00-namespace.yaml -f 10-mongodb-secret.yaml -f 11-mongodb-statefulset.yaml \
              -f 60-networkpolicies.yaml -f 61-pdb.yaml -f 40-ingress.yaml

sed "s|BACKEND_IMAGE_PLACEHOLDER|$REG/mern-devops-dev/backend:$TAG|" 20-backend.yaml | kubectl apply -f -
sed "s|FRONTEND_IMAGE_PLACEHOLDER|$REG/mern-devops-dev/frontend:$TAG|" 30-frontend.yaml | kubectl apply -f -
sed "s|ETL_IMAGE_PLACEHOLDER|$REG/mern-devops-dev/etl:$TAG|" 50-etl-cronjob.yaml | kubectl apply -f -
```

---

## Verification

```bash
# Pods up
kubectl -n mern get pods,svc,ingress

# MongoDB connected
kubectl -n mern logs deploy/backend | grep -i mongo

# Endpoints
ALB=$(kubectl -n mern get ingress mern-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -sf http://$ALB/healthcheck/
curl -sf http://$ALB/record/
curl -sf -X POST http://$ALB/record \
     -H 'content-type: application/json' \
     -d '{"name":"Ada","position":"Eng","level":"Senior"}'

# CronJob actually firing
kubectl -n mern get cronjob etl
kubectl -n mern get jobs --sort-by=.metadata.creationTimestamp | tail -5

# Logs in CloudWatch
aws logs tail "/aws/eks/mern-devops-dev-eks/application" --since 10m --follow
```

---

## Logging & alerts

- **Fluent Bit** runs as a DaemonSet, tails `/var/log/containers/*.log` on each
  node, enriches with Kubernetes metadata, and ships to CloudWatch:
  - `application` — every container's stdout/stderr (frontend, backend,
    mongodb, etl)
  - `host` — kubelet journal
  - `platform` — control plane logs (enabled at the cluster level by Terraform)

- **Alarms** (defined in `terraform/observability.tf`):
  - `<project>-backend-5xx` — fires when the backend access log shows
    >5 HTTP 5xx in any 5-minute window
  - `<project>-node-cpu-high` — fires when any worker node sustains >80% CPU
    for 10 minutes (uses Container Insights)

- **Notification path**: alarm → `SNS topic <project>-alerts` → email
  subscription (provisioned only if `alert_email` is set in `terraform.tfvars`).
  Confirm the SNS subscription email after `terraform apply`.

---

## Security posture

- Worker nodes live in **private subnets**; only the ALB has public IPs.
- All container images run as **non-root** with `readOnlyRootFilesystem` and
  `drop: ALL` capabilities (where the workload allows).
- **NetworkPolicies** enforce least-privilege traffic: the frontend can only
  reach the backend, the backend the database — nothing else can.
- ECR repos are **immutable** + scanned on push, with lifecycle policies that
  expire untagged images after 1 day.
- AWS authentication uses **IRSA** (per-pod IAM) and **OIDC** (CI), so no
  long-lived AWS keys exist anywhere.
- **Secrets** are referenced from K8s `Secret` objects; the committed values
  are placeholders. For real environments, swap in
  [External Secrets Operator](https://external-secrets.io/) backed by AWS
  Secrets Manager, or use SealedSecrets.

---

## Tear-down

```bash
# 1. Drain the cluster of LB-backed services first (or the ALB will block VPC delete)
kubectl -n mern delete ingress mern-ingress
kubectl -n mern delete svc --all

# 2. Helm-managed addons
helm -n kube-system uninstall aws-load-balancer-controller || true

# 3. Terraform
cd "DevOps-Case-Study/terraform"
terraform destroy
```

---

## Challenges encountered & how they were solved

> Per the brief: showing real-world problem-solving.

1. **React URLs were hardcoded to `http://localhost:5050`.** Direct calls
   from the browser to a backend Service don't work in K8s, and CORS-from-ALB
   is messy. Fixed by routing all API calls through the frontend's nginx
   (`location /record/`, `/healthcheck/`) and updating the React components
   to use a relative `API_BASE` (env-driven, defaults to empty). Single
   public hostname, no CORS, dev-and-prod parity.

2. **MongoDB needs persistent storage on EKS.** Out of the box EKS doesn't
   ship the EBS CSI driver, so PVCs hang in `Pending`. Added it as a managed
   add-on in Terraform with an IRSA role attached
   (`module.ebs_csi_irsa_role`) and a `gp3` StorageClass with
   `WaitForFirstConsumer` so the volume is created in the same AZ as the
   pod that mounts it.

3. **Frontend nginx 8080 vs 80.** The official `nginx:alpine` image ships
   a config that listens on 80 — fine for root, broken for the unprivileged
   `nginx` user we drop to. Pinned the listener to 8080 inside the
   container, then `targetPort: 8080` on the Service while keeping the
   external port at 80. Same image works for `docker compose` and K8s.

4. **`dotenv` warning when `config.env` is missing.** The provided
   `loadEnvironment.mjs` always tried to read `./config.env`, which is a
   noisy warning in containers where env vars come from K8s. Made the
   load conditional on `fs.existsSync` — env vars set by the orchestrator
   take precedence either way.

5. **`kubernetes.io/role/elb` subnet tags.** Forgetting these tags is the
   #1 reason ALB Ingress sits in `Pending` forever. Added them to both
   public and private subnet tags in `vpc.tf`.

6. **Cron schedule timezone.** EKS nodes' kubelet runs in UTC; the brief
   says "every hour" — added `timeZone: "UTC"` explicitly so it's
   unambiguous, plus `concurrencyPolicy: Forbid` and
   `activeDeadlineSeconds: 1800` to prevent stuck runs from piling up.

7. **CloudWatch metric filter quoting.** Filter patterns are notorious for
   silent mismatches; ours uses the JSON form (`$.kubernetes.container_name`)
   to target only the `backend` container's logs, then a regex on the body
   to catch the 5xx status code.

---

## What's intentionally out of scope

- **HTTPS / custom domain.** Stub annotations are present in
  `40-ingress.yaml`; bring your own ACM cert and Route53 record to enable.
- **Cluster autoscaling at the node level.** The HPAs scale pods; for
  node scaling, install Karpenter or Cluster Autoscaler.
- **MongoDB high availability.** Single-replica StatefulSet — fine for
  this exercise. Production should use MongoDB Atlas (then point
  `ATLAS_URI` at it and delete the in-cluster StatefulSet) or DocumentDB.
- **End-to-end tests.** The Cypress harness in `client/cypress/` is left
  unconfigured — wire it up in `ci.yml` if needed.
