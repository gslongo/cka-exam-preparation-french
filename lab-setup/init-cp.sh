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

# Attendre que les CRD tigera soient ÉTABLIES (servies par l'API), pas seulement créées.
# `kubectl get crd` réussit dès que l'objet CRD existe, mais l'API server peut ne pas encore
# servir le kind → « no matches for kind Installation ». `--for=condition=established` lève l'ambiguïté.
until kubectl get crd installations.operator.tigera.io apiservers.operator.tigera.io >/dev/null 2>&1; do
  echo "En attente des CRD tigera..."
  sleep 3
done
kubectl wait --for=condition=established --timeout=120s \
  crd/installations.operator.tigera.io crd/apiservers.operator.tigera.io

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

# --- 4b. Helm (compétence CKA « packaging » : install/upgrade de charts) ---
# Pré-installé comme sur le vrai examen. Idempotent.
if ! command -v helm >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# --- 4c. metrics-server (kubectl top + HPA) avec --kubelet-insecure-tls ---
# kubeadm utilise des certifs kubelet auto-signés -> flag insecure requis en lab.
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# --- 4d. crictl (cri-tools) : debug bas niveau du runtime containerd ---
# Pré-installé comme sur le vrai examen (compétence « Troubleshooting »). Idempotent.
if ! command -v crictl >/dev/null 2>&1; then
  CRICTL_VER=$(curl -s https://api.github.com/repos/kubernetes-sigs/cri-tools/releases/latest | grep -oP '"tag_name": "\K[^"]+')
  curl -fsSL "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VER}/crictl-${CRICTL_VER}-linux-amd64.tar.gz" | tar -C /usr/local/bin -xz
fi
cat > /etc/crictl.yaml <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
EOF

# --- 4e. Gateway API (CRDs standard) : successeur d'Ingress, sans contrôleur ---
# Les CRDs suffisent pour créer/valider GatewayClass/Gateway/HTTPRoute en lab.
if ! kubectl get crd httproutes.gateway.networking.k8s.io >/dev/null 2>&1; then
  GWAPI_VER=$(curl -s https://api.github.com/repos/kubernetes-sigs/gateway-api/releases/latest | grep -oP '"tag_name": "\K[^"]+')
  kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GWAPI_VER}/standard-install.yaml"
fi

# --- 5. Alias & completion pour la session vagrant ---
cat >> /home/vagrant/.bashrc <<'EOF'

# --- Kubernetes CKA lab ---
alias k=kubectl
export do='--dry-run=client -o yaml'
export now='--force --grace-period=0'
# bash-completion fournit _get_comp_words_by_ref, requis par la complétion kubectl
[ -f /usr/share/bash-completion/bash_completion ] && source /usr/share/bash-completion/bash_completion
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
EOF

echo "✅ init-cp.sh done — cluster prêt, join-command exporté vers /vagrant/join-command.sh"
