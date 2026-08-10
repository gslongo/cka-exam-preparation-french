#!/usr/bin/env bash
# install-common.sh — runtime + kubeadm sur tous les nodes (Ubuntu 22.04, K8s 1.34)
set -euxo pipefail

# On installe volontairement 1.34 (et PAS 1.35, la version exam) : le cluster est
# initialisé en 1.34 pour pouvoir s'entraîner à l'upgrade kubeadm 1.34 → 1.35
# (compétence CKA « Cluster Architecture »). Passer à "1.35" ici pour partir direct
# en version exam sans exercice d'upgrade.
K8S_MINOR="1.34"

# --- 1. Prérequis kernel + sysctl ---
# Swap OFF de façon *persistante au reboot* : la box bento a une ligne fstab
# séparée par des TABS (`/swap.img\tnone\tswap ...`) → commenter avec [[:space:]]
# (pas un espace littéral, sinon le sed rate la ligne et swap revient au reboot,
# ce qui fait crasher kubelet : "running with swap on is not supported").
swapoff -a
sed -ri '/^[^#]*[[:space:]]swap[[:space:]]/ s/^/#/' /etc/fstab
systemctl mask swap.img.swap 2>/dev/null || true   # empêche la ré-activation par systemd

cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# --- 2. containerd (Ubuntu package suffit pour lab) ---
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y containerd apt-transport-https ca-certificates curl gpg bash-completion

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# --- 3. Repo Kubernetes (pinné sur ${K8S_MINOR}) ---
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# --- 4. Utiliser l'IP privée pour le kubelet (sinon prend l'IP NAT vagrant) ---
NODE_IP=$(ip -4 addr show enp0s8 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || \
          ip -4 addr show eth1     2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)
if [ -n "${NODE_IP:-}" ]; then
  echo "KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}" > /etc/default/kubelet
fi

# --- 5. crictl config (utile pour debug plus tard) ---
cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

echo "✅ install-common.sh done on $(hostname)"
