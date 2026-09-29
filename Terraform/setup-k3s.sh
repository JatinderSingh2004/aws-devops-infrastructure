#!/bin/bash

set -e

echo "========================================"
echo " DevOps Portfolio - EC2 Bootstrap"
echo "========================================"

# --------------------------------------------------
# Configuration supplied by Terraform
# --------------------------------------------------

AWS_REGION="us-east-1"
ECR_REPOSITORY_URL="${ECR_REPOSITORY_URL}"

if [ -z "$ECR_REPOSITORY_URL" ]; then
    echo "ERROR: ECR_REPOSITORY_URL is not set."
    exit 1
fi

echo "ECR Repository: $ECR_REPOSITORY_URL"
echo "AWS Region: $AWS_REGION"


# --------------------------------------------------
# 1. Install AWS CLI
# --------------------------------------------------
# --------------------------------------------------
# 1. Install k3s
# --------------------------------------------------

echo ""
echo "=== Installing k3s ==="

if ! command -v k3s >/dev/null 2>&1; then
    curl -sfL https://get.k3s.io | sh -
else
    echo "k3s is already installed."
fi

echo "k3s installation complete."
echo ""
echo "=== Installing AWS CLI ==="

sudo apt update
sudo apt install -y awscli


# --------------------------------------------------
# 2. Wait for k3s
# --------------------------------------------------

echo ""
echo "=== Waiting for k3s ==="

until sudo kubectl get nodes >/dev/null 2>&1; do
    echo "Waiting for k3s..."
    sleep 5
done

echo "k3s is ready."


# --------------------------------------------------
# 3. Wait for the node to become Ready
# --------------------------------------------------

echo ""
echo "=== Waiting for Kubernetes node ==="

until sudo kubectl get nodes --no-headers 2>/dev/null | grep -q " Ready "; do
    echo "Waiting for node to become Ready..."
    sleep 5
done

echo "Kubernetes node is Ready."


# --------------------------------------------------
# 4. Get ECR authentication password
# --------------------------------------------------

echo ""
echo "=== Getting ECR authentication password ==="

ECR_PASSWORD=$(aws ecr get-login-password --region "$AWS_REGION")

if [ -z "$ECR_PASSWORD" ]; then
    echo "ERROR: Failed to obtain ECR authentication password."
    exit 1
fi

echo "ECR authentication successful."


# --------------------------------------------------
# 5. Create Kubernetes ECR pull secret
# --------------------------------------------------

echo ""
echo "=== Creating ECR pull secret ==="

sudo kubectl delete secret ecr-registry-secret \
    --ignore-not-found

sudo kubectl create secret docker-registry ecr-registry-secret \
    --docker-server="$ECR_REPOSITORY_URL" \
    --docker-username=AWS \
    --docker-password="$ECR_PASSWORD"

echo "ECR pull secret created."


# --------------------------------------------------
# 6. Create Kubernetes Deployment
# --------------------------------------------------

echo ""
echo "=== Creating Deployment ==="

cat <<EOF | sudo kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: devops-portfolio-app
spec:
  replicas: 1

  selector:
    matchLabels:
      app: devops-portfolio-app

  template:
    metadata:
      labels:
        app: devops-portfolio-app

    spec:
      imagePullSecrets:
        - name: ecr-registry-secret

      containers:
        - name: app
          image: ${ECR_REPOSITORY_URL}:latest

          ports:
            - containerPort: 5001
EOF

echo "Deployment created."


# --------------------------------------------------
# 7. Create ClusterIP Service
# --------------------------------------------------

echo ""
echo "=== Creating Service ==="

cat <<EOF | sudo kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: devops-portfolio-service

spec:
  type: ClusterIP

  selector:
    app: devops-portfolio-app

  ports:
    - port: 5001
      targetPort: 5001
EOF

echo "Service created."


# --------------------------------------------------
# 8. Create Traefik Ingress
# --------------------------------------------------

echo ""
echo "=== Creating Ingress ==="

cat <<EOF | sudo kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: devops-portfolio-ingress

spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix

            backend:
              service:
                name: devops-portfolio-service
                port:
                  number: 5001
EOF

echo "Ingress created."


# --------------------------------------------------
# 9. Wait for application rollout
# --------------------------------------------------

echo ""
echo "=== Waiting for application rollout ==="

sudo kubectl rollout status \
    deployment/devops-portfolio-app \
    --timeout=180s


# --------------------------------------------------
# 10. Show final status
# --------------------------------------------------

echo ""
echo "========================================"
echo " Setup Complete"
echo "========================================"

echo ""
echo "=== Nodes ==="
sudo kubectl get nodes

echo ""
echo "=== Pods ==="
sudo kubectl get pods

echo ""
echo "=== Services ==="
sudo kubectl get svc

echo ""
echo "=== Ingress ==="
sudo kubectl get ingress

echo ""
echo "========================================"
echo " Application deployed successfully"
echo "========================================"