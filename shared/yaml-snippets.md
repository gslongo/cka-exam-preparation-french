# YAML — snippets prêts à copier

> Manifests minimaux, indentation 2 espaces, forme compacte quand possible. Objectif = **gain de temps**, pas complétude.

## Pod

```yaml
apiVersion: v1
kind: Pod
metadata: { name: p, labels: { app: web } }
spec:
  containers:
  - { name: c, image: nginx:1.25, ports: [{ containerPort: 80 }] }
```

### Pod avec resources + probes + env

```yaml
apiVersion: v1
kind: Pod
metadata: { name: p }
spec:
  containers:
  - name: c
    image: nginx:1.25
    ports: [{ containerPort: 80 }]
    env:
    - { name: LOG_LEVEL, value: debug }
    - name: DB_PW
      valueFrom: { secretKeyRef: { name: db, key: password } }
    envFrom:
    - configMapRef: { name: app-cfg }
    resources:
      requests: { cpu: 100m, memory: 128Mi }
      limits:   { cpu: 500m, memory: 256Mi }
    readinessProbe: { httpGet: { path: /, port: 80 }, periodSeconds: 5 }
    livenessProbe:  { httpGet: { path: /, port: 80 }, periodSeconds: 10 }
```

### Multi-container (sidecar log shipper)

```yaml
apiVersion: v1
kind: Pod
metadata: { name: multi }
spec:
  volumes: [{ name: logs, emptyDir: {} }]
  containers:
  - name: app
    image: myapp:1.0
    volumeMounts: [{ name: logs, mountPath: /var/log/app }]
  - name: shipper
    image: fluent/fluent-bit
    volumeMounts: [{ name: logs, mountPath: /var/log/app, readOnly: true }]
```

### Init container

```yaml
apiVersion: v1
kind: Pod
metadata: { name: with-init }
spec:
  initContainers:
  - name: wait-db
    image: busybox
    command: [sh, -c, "until nc -z db 5432; do sleep 1; done"]
  containers:
  - { name: app, image: myapp:1.0 }
```

## Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: web, labels: { app: web } }
spec:
  replicas: 3
  selector: { matchLabels: { app: web } }
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxUnavailable: 1, maxSurge: 1 }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
      - { name: c, image: nginx:1.25, ports: [{ containerPort: 80 }] }
```

## DaemonSet (avec toutes tolérations)

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: agent, namespace: kube-system }
spec:
  selector: { matchLabels: { app: agent } }
  template:
    metadata: { labels: { app: agent } }
    spec:
      tolerations: [{ operator: Exists }]
      hostNetwork: true
      containers: [{ name: a, image: myrepo/agent:1.0 }]
```

## StatefulSet + Headless Service

```yaml
apiVersion: v1
kind: Service
metadata: { name: web }
spec:
  clusterIP: None
  selector: { app: web }
  ports: [{ port: 80 }]
---
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: web }
spec:
  serviceName: web
  replicas: 3
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
      - name: c
        image: nginx:1.25
        volumeMounts: [{ name: data, mountPath: /data }]
  volumeClaimTemplates:
  - metadata: { name: data }
    spec:
      accessModes: [ReadWriteOnce]
      resources: { requests: { storage: 1Gi } }
```

## Job / CronJob

```yaml
apiVersion: batch/v1
kind: Job
metadata: { name: once }
spec:
  completions: 5
  parallelism: 2
  backoffLimit: 3
  template:
    spec:
      restartPolicy: OnFailure
      containers: [{ name: c, image: busybox, command: [echo, hi] }]
---
apiVersion: batch/v1
kind: CronJob
metadata: { name: backup }
spec:
  schedule: "0 3 * * *"
  concurrencyPolicy: Forbid          # Allow | Forbid | Replace
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers: [{ name: c, image: busybox, command: [/backup.sh] }]
```

## Service (tous types)

```yaml
apiVersion: v1
kind: Service
metadata: { name: web }
spec:
  selector: { app: web }
  ports: [{ port: 80, targetPort: 80 }]
  type: ClusterIP                    # ou NodePort / LoadBalancer / ExternalName
```

### NodePort explicite

```yaml
spec:
  type: NodePort
  ports: [{ port: 80, targetPort: 80, nodePort: 30080 }]
```

### ExternalName

```yaml
spec:
  type: ExternalName
  externalName: db.internal.example.com
```

## Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: web }
spec:
  ingressClassName: nginx
  tls: [{ hosts: [app.example.com], secretName: web-tls }]
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend: { service: { name: web, port: { number: 80 } } }
```

## NetworkPolicy — patterns essentiels

```yaml
# Deny-all (baseline)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: deny-all }
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

```yaml
# Allow only from label + DNS egress (utile 90 % du temps)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: api }
spec:
  podSelector: { matchLabels: { app: api } }
  policyTypes: [Ingress, Egress]
  ingress:
  - from: [{ podSelector: { matchLabels: { app: web } } }]
    ports: [{ port: 8080 }]
  egress:
  - to:                               # DNS toujours
    - namespaceSelector: {}
      podSelector: { matchLabels: { k8s-app: kube-dns } }
    ports: [{ port: 53, protocol: UDP }]
```

## ConfigMap / Secret

```yaml
apiVersion: v1
kind: ConfigMap
metadata: { name: app-cfg }
data:
  LOG_LEVEL: info
  config.yaml: |
    server:
      port: 8080
---
apiVersion: v1
kind: Secret
metadata: { name: db }
type: Opaque
stringData:                           # texte brut → encodé auto
  username: admin
  password: s3cr3t
```

## PersistentVolume / PersistentVolumeClaim

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data }
spec:
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 5Gi } }
  storageClassName: standard
```

## RBAC

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: { name: bot }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: reader }
rules:
- { apiGroups: [""], resources: [pods, pods/log], verbs: [get, list, watch] }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: bot-reads }
subjects: [{ kind: ServiceAccount, name: bot }]
roleRef: { kind: Role, name: reader, apiGroup: rbac.authorization.k8s.io }
```

## ResourceQuota + LimitRange

```yaml
apiVersion: v1
kind: ResourceQuota
metadata: { name: q, namespace: dev }
spec:
  hard:
    pods: "20"
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
---
apiVersion: v1
kind: LimitRange
metadata: { name: default-limits, namespace: dev }
spec:
  limits:
  - type: Container
    default:        { cpu: 500m, memory: 256Mi }
    defaultRequest: { cpu: 100m, memory: 128Mi }
```

## PodDisruptionBudget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: web-pdb }
spec:
  minAvailable: 2                    # ou maxUnavailable: 1
  selector: { matchLabels: { app: web } }
```

## HPA v2

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: web }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: web }
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource: { name: cpu, target: { type: Utilization, averageUtilization: 70 } }
```
