# Glossaire Kubernetes — CKA

> Termes techniques essentiels. **Anglais conservé** pour les noms d'objets et concepts standards.

## A

- **Admission Controller** : plugin API server qui valide/modifie une requête après authn/authz. Ex : `NamespaceLifecycle`, `LimitRanger`, `PodSecurity`, `ValidatingAdmissionWebhook`.
- **Affinity** : règles préférentielles pour rapprocher/séparer Pods de nodes ou d'autres Pods.
- **API Group** : namespace logique d'une ressource API (`core`, `apps`, `networking.k8s.io`, `storage.k8s.io`…).
- **API Server** (`kube-apiserver`) : point d'entrée unique du cluster. RESTful, authent + authz + admission.
- **Annotation** : metadata clé/valeur libre, non indexée, non utilisée pour selection.

## B

- **BackoffLimit** : nombre de tentatives d'un Job avant abandon.
- **Bookmark event** : type d'event `watch` qui indique la position ResourceVersion (perf).

## C

- **ClusterIP** : type de Service exposant une IP virtuelle interne au cluster.
- **ClusterRole** : Role cluster-scoped.
- **CNI** (Container Network Interface) : spec pour plugins réseau Pods (Calico, Cilium, Flannel…).
- **ConfigMap** : objet stockant config non-sensible sous forme clé/valeur ou fichiers.
- **Container Runtime Interface (CRI)** : spec entre kubelet et runtime (containerd, CRI-O).
- **CoreDNS** : DNS interne du cluster, Deployment dans `kube-system`.
- **Cordon** : marquer un node `unschedulable` (aucun nouveau Pod).
- **CRD** (CustomResourceDefinition) : ajouter des ressources custom à l'API.
- **crictl** : CLI de debug pour l'interface CRI (à utiliser sur le node).
- **CSI** (Container Storage Interface) : spec pour drivers de storage.

## D

- **DaemonSet** : controller assurant 1 Pod par node.
- **Deployment** : controller stateless avec rolling updates via ReplicaSets.
- **Drain** : `cordon` + eviction des Pods (respectant PDB).

## E

- **Endpoints / EndpointSlices** : liste des IPs de Pods `Ready` derrière un Service.
- **Ephemeral Container** : container ajouté à un Pod en cours (debug, GA 1.25).
- **etcd** : store distribué (RAFT) qui contient tout l'état du cluster.
- **Eviction** : suppression d'un Pod par un contrôleur (API-driven) ou par le kubelet (node pressure).

## F

- **Finalizer** : identifiant sur `metadata.finalizers` qui bloque la suppression tant que non retiré.

## G

- **Gateway API** : successeur d'Ingress, GA 1.31 (Gateway, HTTPRoute).
- **GVR** (Group/Version/Resource) : triplet identifiant une ressource dans l'API.

## H

- **Headless Service** : Service avec `clusterIP: None`, retourne toutes les IPs de Pods.
- **HPA** (Horizontal Pod Autoscaler) : autoscale `replicas` selon metrics.

## I

- **Immutable field** : champ que K8s refuse de modifier après création (ex : `Deployment.spec.selector`).
- **Ingress** : ressource L7 avec routing host/path.
- **Ingress Controller** : Pod qui implémente les Ingress (nginx, Traefik…).
- **Init container** : container exécuté séquentiellement avant les containers principaux.
- **IPVS** : mode kube-proxy basé sur IP Virtual Server (perf sur gros clusters).

## J

- **Job** : controller pour tâche batch terminale.
- **JSONPath** : format `-o jsonpath='...'` pour extraire des champs.

## K

- **kubeadm** : outil officiel de bootstrap d'un cluster.
- **kubectl** : CLI client de l'API server.
- **kubelet** : agent K8s sur chaque node.
- **kube-proxy** : programme les règles réseau des Services (iptables/ipvs/nftables).
- **Kustomize** : templating natif kubectl (`-k`), overlays.

## L

- **Label** : metadata indexée clé/valeur, utilisée par selectors.
- **LimitRange** : contraintes de resources par container/pod dans un namespace.
- **Liveness probe** : sonde ; échec → kubelet redémarre le container.

## M

- **metrics-server** : composant fournissant `kubectl top` (CPU/mem instantanés).

## N

- **Namespace** : partition logique cluster (ressources scoped).
- **NetworkPolicy** : firewall L3/L4 pour Pods (nécessite CNI compatible).
- **Node** : machine (VM/bare metal) qui exécute des Pods.
- **NodePort** : Service exposé sur un port du node (30000-32767).

## O

- **Operator** : combinaison CRD + controller pour gérer une app complexe (Postgres, Kafka…).
- **OOMKilled** : container tué pour dépassement mémoire (exit code 137).

## P

- **PDB** (PodDisruptionBudget) : limite les disruptions volontaires (drain).
- **PersistentVolume** (PV) : représentation d'un volume backend.
- **PersistentVolumeClaim** (PVC) : demande de volume par une app.
- **Pod** : plus petite unité déployable ; 1+ containers partageant net/IPC/UTS.
- **PriorityClass** : priorité de scheduling + préemption.
- **Probe** : sonde `readiness`/`liveness`/`startup`.

## Q

- **QoS Class** : `Guaranteed` / `Burstable` / `BestEffort` — dérivée des requests/limits.
- **Quorum** : majorité des membres etcd ((N/2)+1).

## R

- **RBAC** : Role-Based Access Control (Roles/ClusterRoles + Bindings).
- **Readiness probe** : sonde ; échec → retire le Pod des endpoints (sans le tuer).
- **Reclaim policy** : `Retain` / `Delete` / `Recycle` (deprecated).
- **ReplicaSet** : controller bas niveau assurant N Pods identiques.
- **Requests / Limits** : ressources réservées / plafond.
- **RollingUpdate** : stratégie de mise à jour progressive (`maxSurge`, `maxUnavailable`).

## S

- **Scheduler** (`kube-scheduler`) : attribue les Pods aux Nodes.
- **Secret** : objet stockant données sensibles (base64, à chiffrer côté etcd via `EncryptionConfig`).
- **Selector** : `matchLabels` ou `matchExpressions` pour cibler Pods/Services.
- **Service** : abstraction stable devant un ensemble de Pods.
- **ServiceAccount** (SA) : identité d'un Pod pour parler à l'API.
- **Sidecar** : container secondaire dans un Pod (log shipper, proxy…).
- **StatefulSet** : controller stateful (identité + volume stable).
- **StorageClass** : template pour dynamic provisioning.

## T

- **Taint** : marque sur un node repoussant les Pods sans tolerations correspondantes.
- **Tolerations** : Pod-side ; tolère un taint.
- **TopologySpreadConstraints** : répartition Pods entre zones/hosts.

## U

- **Uncordon** : rétablir un node comme schedulable.
- **Upgrade path** : kubeadm supporte upgrade **1 mineure à la fois** (1.34 → 1.35, pas 1.33 → 1.35).

## V

- **VolumeAttachment** : ressource K8s traçant qu'un volume CSI est attaché à un node.
- **volumeClaimTemplate** : template PVC dans un StatefulSet.

## W

- **WaitForFirstConsumer** : `volumeBindingMode` qui retarde la création du PV jusqu'au scheduling.
- **Webhook** : callback HTTP (admission, conversion CRD).

## Sigles à connaître

| Sigle | Signification |
|---|---|
| CNI | Container Network Interface |
| CRI | Container Runtime Interface |
| CSI | Container Storage Interface |
| CRD | Custom Resource Definition |
| CP | Control Plane |
| DS | DaemonSet |
| ETCD | Étymologie : `/etc` + distributed |
| HPA / VPA / CA | Horizontal / Vertical / Cluster Autoscaler |
| LB | Load Balancer |
| PDB | Pod Disruption Budget |
| PSP | Pod Security Policy (**supprimé en 1.25**, remplacé par Pod Security Admission / PSA) |
| PV / PVC | PersistentVolume / …Claim |
| QoS | Quality of Service |
| RBAC | Role-Based Access Control |
| RS | ReplicaSet |
| SA | ServiceAccount |
| SC | StorageClass |
| SS | StatefulSet |
| SVC | Service |
