# Docmost on EKS

This directory contains a repository-owned Helm chart for the official Docmost container, plus a Kustomize secret and namespace preflight. The chart has no subcharts and does not install PostgreSQL, Redis/Valkey, an ingress controller, or other services. It is pinned to the official `docmost/docmost:0.96.0` image.

Docmost's upstream self-hosting guide documents Docker Compose rather than Helm. It requires PostgreSQL and Redis, uses `APP_URL`, `APP_SECRET`, `DATABASE_URL`, and `REDIS_URL`, stores local uploads under `/app/data/storage`, and exposes `/api/health`. It also requires WebSockets through any reverse proxy. The upstream Redis TLS issue for `rediss://` was fixed before v0.96.0; that version's Redis config passes the parsed TLS options to the Redis client.

## Prerequisites

- The EKS cluster is reachable from the operator machine. Configure `kubectl` for `aws-eks-platform-lab-eks` in the selected Region (`us-east-2`) using your local AWS profile.
- Helm, Kustomize, kubectl, and AWS CLI are installed.
- The RDS PostgreSQL and ElastiCache Valkey endpoints from Terraform outputs are reachable from EKS nodes.
- The Service remains `ClusterIP`; the chart Ingress creates a public ALB through the AWS Load Balancer Controller. The default listeners use HTTP until you supply a DNS name and ACM certificate ARN for HTTPS. Do not submit credentials over the HTTP endpoint.
- A dedicated PostgreSQL application role owns the `docmost` database for migrations. Install the `unaccent` and `pg_trgm` extensions during the one-time bootstrap with the RDS-managed master credential; do not use that credential for the application.

## Prepare local credentials

Copy the example and edit the ignored local file. Do not commit it or paste its values into command arguments, logs, or terminal transcripts:

```sh
cp deploy/docmost/runtime.env.example deploy/docmost/runtime.env
chmod 600 deploy/docmost/runtime.env
```

Set `APP_SECRET` to a newly generated random value with at least 32 characters (for example, `openssl rand -hex 32`). Replace the PostgreSQL URL host and password with the RDS endpoint and a password for the dedicated application role. Keep the `sslmode=require` query so the connection uses TLS. Replace the Valkey host and AUTH token; keep the `rediss://` scheme to use TLS. Percent-encode URL-reserved characters in both passwords. The RDS and Valkey endpoints can be read from the corresponding Terraform outputs without putting endpoint identifiers into tracked files.

The RDS endpoint is private, so bootstrap from a temporary PostgreSQL client pod in EKS. Terraform created the `docmost_admin` password automatically; you do **not** create or retrieve it through `psql`. In the AWS Management Console, select `us-east-2`, open **Secrets Manager → Secrets**, find the ARN shown by `terraform output docmost_postgres_master_secret_arn`, then choose **Retrieve secret value**. Copy the `password` field from that JSON for the initial `psql` login. The `docmost_app` password is separate; you choose it later with `\password docmost_app`.

From the repository root, start the client pod and wait for it before opening `psql`. This ensures its password prompt has an attached terminal. The commands below copy the downloaded RDS CA bundle into the temporary pod so `verify-full` can check the server certificate and hostname:

```sh
RDSHOST="$(terraform -chdir=terraform/platform output -raw docmost_postgres_address)"
kubectl -n default run pg-client --restart=Never --image=postgres:16 --command -- sleep 3600
kubectl -n default wait --for=condition=Ready pod/pg-client --timeout=120s
kubectl -n default exec -i pg-client -- sh -c 'cat > /tmp/global-bundle.pem' < ./global-bundle.pem
kubectl -n default exec -it pg-client -- env PGSSLMODE=verify-full PGSSLROOTCERT=/tmp/global-bundle.pem \
  psql -h "$RDSHOST" -U docmost_admin -d docmost -W
```

`psql` now prompts for the master password; enter it at the prompt. It is absent from the command line. After finishing the SQL below and exiting `psql`, remove the pod with `kubectl -n default delete pod pg-client`.

In `psql`, run:

```sql
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE ROLE docmost_app LOGIN;
ALTER DATABASE docmost OWNER TO docmost_app;
\password docmost_app
```

The `\password` prompt hides the new role's password. Use that role in `DATABASE_URL`, with its password URL-encoded. Do not put either password in a tracked SQL file or shell command line. If the role already exists, skip the `CREATE ROLE` statement.

`runtime.env.example` is a placeholder template only. Kustomize refuses to build until the ignored `runtime.env` exists. The generated Kubernetes Secret has a stable name; after changing its contents, restart the Docmost deployment so the process reloads its environment.

## Install

The ALB itself is controller-managed: Terraform provisions its IAM policy/role, Pod Identity association, and public-subnet discovery tags; the Kubernetes Ingress below asks the controller to create and reconcile the ALB. The Terraform CI workflow does not connect to the Kubernetes API. Install the controller from the operator machine after Terraform has applied its prerequisites:

```sh
CLUSTER="$(terraform -chdir=terraform/platform output -raw eks_cluster_name)"
REGION="us-east-2"
VPC_ID="$(terraform -chdir=terraform/platform output -raw vpc_id)"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --version 1.14.1 \
  --set clusterName="$CLUSTER" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller
kubectl -n kube-system rollout status deployment/aws-load-balancer-controller --timeout=180s
```

The pinned AWS Helm chart `1.14.1` packages controller `v2.14.1`; the matching controller IAM actions are maintained in Terraform. Region and VPC are explicit so the controller does not need node metadata access. EKS Pod Identity Agent is already configured as an EKS add-on, and Terraform creates the controller's Pod Identity association.

Kustomize creates only the `docmost` namespace and runtime Secret; Helm owns the application Deployment, Service, and Ingress:

```sh
kubectl apply --server-side -k deploy/docmost
helm upgrade --install docmost deploy/docmost/chart \
  --namespace docmost \
  --values deploy/docmost/chart/values.yaml
```

The Ingress starts with a public HTTP listener so the ALB DNS name can be discovered. Use HTTP only to confirm the load balancer responds; do not enter credentials or invite users until HTTPS is configured. Get the assigned URL and set it as `appUrl` in `chart/values.yaml`, then upgrade the release so Docmost generates correct absolute links:

```sh
kubectl -n docmost get ingress docmost
```

For HTTPS, point a DNS name at the ALB, request/validate an ACM certificate in `us-east-2`, then set `ingress.host`, `ingress.certificateArn`, and `appUrl: "https://your-hostname"` in the values file and run the same Helm upgrade. The chart then redirects HTTP to HTTPS. The app needs the HTTPS route to support WebSockets.

The first command generates the Secret locally and sends it to the Kubernetes API without printing its contents. The second command creates the Helm release. Neither command is run as part of preparing these files.

To reach the internal Service for an initial check, use a local port-forward:

```sh
kubectl -n docmost port-forward service/docmost 3000:3000
```

Then open `http://localhost:3000` for local access, or use the Ingress URL after configuring `appUrl`. Docmost's first setup screen creates the initial workspace owner.

## Storage and limits

Uploads use an `emptyDir` for this minimal lab install because the EKS cluster does not currently include an EBS CSI driver or object-storage integration. Files in `/app/data/storage` are lost when the pod is replaced or rescheduled. This chart runs one replica and is suitable only for a disposable demonstration until durable upload storage is added and verified. PostgreSQL and Valkey remain the persistent data services.

## Remove

After confirming that the application data is no longer needed, remove the Helm release and namespace Secret:

```sh
helm uninstall docmost --namespace docmost
kubectl delete -k deploy/docmost
```

Namespace deletion removes the namespace after the Helm release is removed. The local ignored credential file should be deleted separately when no longer needed.
