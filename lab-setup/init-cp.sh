#!/usr/bin/env bash
# init-cp.sh — kubeadm init sur cp1 + Calico + génération join command
set -euxo pipefail

CP_IP="192.168.56.10"
POD_CIDR="10.244.0.0/16"
CALICO_VERSION="v3.28.1"

# Skip si déjà initialisé (idempotent)
if [ -f /etc/kubernetes/admin.conf ]; then
  echo "cp1 déjà initialisé — skip"
  # Regénérer le join command au cas où
  kubeadm token create --print-join-command > /vagrant/join-command.sh
  chmod 0755 /vagrant/join-command.sh
  exit 0
fi

# --- 1. kubeadm init ---
kubeadm init \
  --apiserver-advertise-address="${CP_IP}" \
  --pod-network-cidr="${POD_CIDR}" \
  --node-name=cp1 \
  --cri-socket=unix:///run/containerd/containerd.sock

# --- 2. kubeconfig pour root ET vagrant ---
mkdir -p /root/.kube
cp -f /etc/kubernetes/admin.conf /root/.kube/config

mkdir -p /home/vagrant/.kube
cp -f /etc/kubernetes/admin.conf /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube

# --- 3. Install Calico via tigera-operator (CIDR customisable) ---
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"

# Attendre que le CRD Installation soit dispo
until kubectl get crd installations.operator.tigera.io >/dev/null 2>&1; do
  echo "En attente du CRD Installation..."
  sleep 3
done

cat <<EOF | kubectl create -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: ${POD_CIDR}
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF

# --- 4. Générer le join command pour les workers ---
kubeadm token create --print-join-command > /vagrant/join-command.sh
chmod 0755 /vagrant/join-command.sh

# --- 5. Alias & completion pour la session vagrant ---
cat >> /home/vagrant/.bashrc <<'EOF'

# --- Kubernetes CKA lab ---
alias k=kubectl
export do='--dry-run=client -o yaml'
export now='--force --grace-period=0'
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
EOF

echo "✅ init-cp.sh done — cluster prêt, join-command exporté vers /vagrant/join-command.sh"
