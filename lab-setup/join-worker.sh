#!/usr/bin/env bash
# join-worker.sh — attend le join command généré par cp1 puis rejoint le cluster
set -euxo pipefail

# Skip si déjà joint (kubelet a un kubeconfig)
if [ -f /etc/kubernetes/kubelet.conf ]; then
  echo "$(hostname) déjà joint au cluster — skip"
  exit 0
fi

# Poll le join command produit par init-cp.sh (max 5 min)
JOIN_FILE="/vagrant/join-command.sh"
TIMEOUT=300
ELAPSED=0
while [ ! -f "${JOIN_FILE}" ] && [ ${ELAPSED} -lt ${TIMEOUT} ]; do
  echo "En attente de ${JOIN_FILE} (généré par cp1)... ${ELAPSED}s"
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

if [ ! -f "${JOIN_FILE}" ]; then
  echo "❌ Timeout : ${JOIN_FILE} introuvable. cp1 est-il démarré ?" >&2
  exit 1
fi

# Exécuter le join (kubeadm join ... --token ... --discovery-token-ca-cert-hash ...)
bash "${JOIN_FILE}" --cri-socket=unix:///run/containerd/containerd.sock --node-name="$(hostname)"

echo "✅ $(hostname) a rejoint le cluster"
