# OpenLDAP Kubernetes Deployment Guide

This guide provides instructions for deploying OpenLDAP in Kubernetes, including TLS/certificate management options.

**Maintainer:** Mario Enrico Ragucci (ghmer) - [openldap@r5i.xyz](mailto:openldap@r5i.xyz)
**Repository:** [https://github.com/ghmer/openldap-container](https://github.com/ghmer/openldap-container)
**License:** MIT

**⚠️ AI GENERATED - VIEWER DISCRETION IS ADVISED ⚠️**

## Table of Contents

- [Prerequisites](#prerequisites)
- [Basic Deployment](#basic-deployment)
- [TLS Configuration Options](#tls-configuration-options)
  - [Option 1: Direct TLS with cert-manager](#option-1-direct-tls-with-cert-manager)
  - [Option 2: Direct TLS with Existing Certificates](#option-2-direct-tls-with-existing-certificates)
  - [Option 3: TLS Termination with Traefik and Let's Encrypt](#option-3-tls-termination-with-traefik-and-lets-encrypt)
- [Initial Data Configuration](#initial-data-configuration)
- [Service Exposure Options](#service-exposure-options)
- [Production Example](#production-example)
- [Operations](#operations)
- [Troubleshooting](#troubleshooting)

## Basic Deployment

### 1. Create Namespace

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openldap
```

### 2. Create Secrets

```bash
kubectl create secret generic openldap-secrets \
  --from-literal=admin-password='admin_password' \
  --from-literal=config-admin-password='config_password' \
  -n openldap
```

### 3. Deploy OpenLDAP (Basic - No TLS)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: openldap
  namespace: openldap
spec:
  type: ClusterIP
  ports:
    - name: ldap
      port: 1389
      targetPort: 1389
  selector:
    app: openldap
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: openldap
  namespace: openldap
spec:
  serviceName: openldap
  replicas: 1
  selector:
    matchLabels:
      app: openldap
  template:
    metadata:
      labels:
        app: openldap
    spec:
      securityContext:
        fsGroup: 1001
        runAsUser: 1001
        runAsNonRoot: true
      containers:
      - name: openldap
        image: garthako/openldap:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 1389
          name: ldap
        env:
        - name: LDAP_BASE_DN
          value: "dc=example,dc=com"
        - name: LDAP_ADMIN_USER
          value: "cn=admin"
        - name: LDAP_ADMIN_PW
          valueFrom:
            secretKeyRef:
              name: openldap-secrets
              key: admin-password
        - name: LDAP_CONFIG_ADMIN_PW
          valueFrom:
            secretKeyRef:
              name: openldap-secrets
              key: config-admin-password
        - name: LDAP_ALLOW_ANON_BINDING
          value: "false"
        volumeMounts:
        - name: data
          mountPath: /var/lib/ldap
        - name: config
          mountPath: /etc/ldap/slapd.d
        livenessProbe:
          tcpSocket:
            port: 1389
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - ldapsearch
            - -x
            - -H
            - ldap://localhost:1389
            - -b
            - dc=example,dc=com
            - -LLL
          initialDelaySeconds: 20
          periodSeconds: 10
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 5Gi
  - metadata:
      name: config
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 1Gi
```

## TLS Configuration Options

### Option 1: Direct TLS with cert-manager

This option configures OpenLDAP to handle TLS directly using certificates from cert-manager.

#### 1. Install cert-manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.18.2/cert-manager.yaml
```

#### 2. Create Certificate Issuer

```yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned-issuer
  namespace: openldap
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: openldap-tls
  namespace: openldap
spec:
  secretName: openldap-tls-secret
  duration: 8760h # 1 year
  renewBefore: 720h # 30 days
  subject:
    organizations:
      - Example Org
  commonName: openldap.openldap.svc.cluster.local
  dnsNames:
    - openldap
    - openldap.openldap
    - openldap.openldap.svc
    - openldap.openldap.svc.cluster.local
  issuerRef:
    name: selfsigned-issuer
    kind: Issuer
```

#### 3. Update StatefulSet for TLS

Add to the StatefulSet:

```yaml
# In spec.template.spec.containers[0].env:
        - name: LDAP_ENABLE_TLS
          value: "true"
        - name: LDAP_TLS_CERT_FILE
          value: "/import/certs/tls.crt"
        - name: LDAP_TLS_KEY_FILE
          value: "/import/certs/tls.key"
        - name: LDAP_TLS_CA_FILE
          value: "/import/certs/ca.crt"

# In spec.template.spec.containers[0].ports:
        - containerPort: 1636
          name: ldaps

# In spec.template.spec.containers[0].volumeMounts:
        - name: tls-certs
          mountPath: /import/certs
          readOnly: true

# In spec.template.spec.volumes:
      volumes:
      - name: tls-certs
        secret:
          secretName: openldap-tls-secret
          defaultMode: 0640
```

Update Service to expose LDAPS:

```yaml
spec:
  ports:
    - name: ldap
      port: 1389
      targetPort: 1389
    - name: ldaps
      port: 1636
      targetPort: 1636
```

### Option 2: Direct TLS with Existing Certificates

#### 1. Create Secret from Existing Certificates

```bash
kubectl create secret generic openldap-tls-secret \
  --from-file=tls.crt=./certs/server.crt \
  --from-file=tls.key=./certs/server.key \
  --from-file=ca.crt=./certs/ca.crt \
  -n openldap
```

#### 2. Update StatefulSet

Use the same configuration as Option 1, step 3.

### Option 3: TLS Termination with Traefik and Let's Encrypt

This option uses Traefik to terminate TLS and forward plain LDAP traffic to the OpenLDAP service. This is ideal for external access with automatic Let's Encrypt certificates.

**Note**: LDAP protocol over HTTP/HTTPS is not standard. This setup uses TCP routing with TLS termination.

#### 1. Install Traefik (if not already installed)

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik -n traefik --create-namespace
```

#### 2. Create Let's Encrypt Certificate Issuer

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: traefik
```

#### 3. Create Certificate for LDAP

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ldap-tls
  namespace: openldap
spec:
  secretName: ldap-tls-secret
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - ldap.example.com  # Replace with your domain
```

#### 4. Deploy OpenLDAP (Plain LDAP - No TLS)

Use the basic deployment from above (without TLS configuration in OpenLDAP itself).

#### 5. Create Traefik IngressRouteTCP

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRouteTCP
metadata:
  name: ldap-ingress
  namespace: openldap
spec:
  entryPoints:
    - websecure  # Traefik HTTPS entrypoint
  routes:
  - match: HostSNI(`ldap.example.com`)
    services:
    - name: openldap
      port: 1389
  tls:
    secretName: ldap-tls-secret
```

#### 6. Alternative: Using Traefik Middleware for LDAPS

For LDAPS (port 636) with TLS passthrough:

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRouteTCP
metadata:
  name: ldaps-ingress
  namespace: openldap
spec:
  entryPoints:
    - ldaps  # Custom entrypoint for LDAPS
  routes:
  - match: HostSNI(`ldap.example.com`)
    services:
    - name: openldap
      port: 1389  # Plain LDAP backend
  tls:
    secretName: ldap-tls-secret
    options:
      name: default
```

Configure Traefik to listen on port 636:

```yaml
# In Traefik values.yaml or configuration
ports:
  ldaps:
    port: 636
    expose: true
    exposedPort: 636
    protocol: TCP
```

#### 7. Client Connection

Clients connect to `ldaps://ldap.example.com:636` where:
- Traefik terminates TLS using Let's Encrypt certificate
- Forwards plain LDAP to OpenLDAP service on port 1389
- Automatic certificate renewal by cert-manager

**Important Considerations for Option 3:**
- TLS is terminated at Traefik, not at OpenLDAP
- Traffic between Traefik and OpenLDAP is unencrypted (use network policies to secure)
- Best for scenarios where you need automatic Let's Encrypt certificates
- Requires proper DNS configuration pointing to your cluster's external IP

## Initial Data Configuration

### Using ConfigMap for LDIF Files

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: openldap-ldif
  namespace: openldap
data:
  01-users.ldif: |
    dn: ou=users,dc=example,dc=com
    objectClass: organizationalUnit
    ou: users

    dn: ou=groups,dc=example,dc=com
    objectClass: organizationalUnit
    ou: groups
  
  02-sample-user.ldif: |
    dn: uid=john,ou=users,dc=example,dc=com
    objectClass: inetOrgPerson
    objectClass: posixAccount
    objectClass: shadowAccount
    uid: john
    cn: John Doe
    sn: Doe
    loginShell: /bin/bash
    uidNumber: 10000
    gidNumber: 10000
    homeDirectory: /home/john
    userPassword: {SSHA}encrypted_password_here
```

Mount in StatefulSet:

```yaml
# In spec.template.spec.containers[0].volumeMounts:
        - name: ldif-files
          mountPath: /import/ldif
          readOnly: true

# In spec.template.spec.volumes:
      - name: ldif-files
        configMap:
          name: openldap-ldif
```

## Service Exposure Options

### Internal Access Only (ClusterIP)

Already configured in basic deployment.

### External Access via LoadBalancer

```yaml
apiVersion: v1
kind: Service
metadata:
  name: openldap-external
  namespace: openldap
spec:
  type: LoadBalancer
  ports:
    - name: ldap
      port: 389
      targetPort: 1389
    - name: ldaps
      port: 636
      targetPort: 1636
  selector:
    app: openldap
```

### External Access via NodePort

```yaml
apiVersion: v1
kind: Service
metadata:
  name: openldap-nodeport
  namespace: openldap
spec:
  type: NodePort
  ports:
    - name: ldap
      port: 1389
      targetPort: 1389
      nodePort: 30389
    - name: ldaps
      port: 1636
      targetPort: 1636
      nodePort: 30636
  selector:
    app: openldap
```

## Production Example

Complete production-ready deployment with direct TLS:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openldap
---
apiVersion: v1
kind: Secret
metadata:
  name: openldap-secrets
  namespace: openldap
type: Opaque
stringData:
  admin-password: "ChangeMe123!"
  config-admin-password: "ChangeMe456!"
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned-issuer
  namespace: openldap
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: openldap-tls
  namespace: openldap
spec:
  secretName: openldap-tls-secret
  duration: 8760h
  renewBefore: 720h
  commonName: openldap.openldap.svc.cluster.local
  dnsNames:
    - openldap
    - openldap.openldap.svc.cluster.local
  issuerRef:
    name: selfsigned-issuer
    kind: Issuer
---
apiVersion: v1
kind: Service
metadata:
  name: openldap
  namespace: openldap
spec:
  type: ClusterIP
  clusterIP: None  # Headless service for StatefulSet
  ports:
    - name: ldap
      port: 1389
      targetPort: 1389
    - name: ldaps
      port: 1636
      targetPort: 1636
  selector:
    app: openldap
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: openldap
  namespace: openldap
spec:
  serviceName: openldap
  replicas: 1
  selector:
    matchLabels:
      app: openldap
  template:
    metadata:
      labels:
        app: openldap
    spec:
      securityContext:
        fsGroup: 1001
        runAsUser: 1001
        runAsNonRoot: true
      containers:
      - name: openldap
        image: garthako/openldap:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 1389
          name: ldap
        - containerPort: 1636
          name: ldaps
        env:
        - name: LDAP_BASE_DN
          value: "dc=example,dc=com"
        - name: LDAP_ADMIN_USER
          value: "cn=admin"
        - name: LDAP_ADMIN_PW
          valueFrom:
            secretKeyRef:
              name: openldap-secrets
              key: admin-password
        - name: LDAP_CONFIG_ADMIN_PW
          valueFrom:
            secretKeyRef:
              name: openldap-secrets
              key: config-admin-password
        - name: LDAP_ENABLE_TLS
          value: "true"
        - name: LDAP_TLS_CERT_FILE
          value: "/import/certs/tls.crt"
        - name: LDAP_TLS_KEY_FILE
          value: "/import/certs/tls.key"
        - name: LDAP_TLS_CA_FILE
          value: "/import/certs/ca.crt"
        - name: LDAP_ALLOW_ANON_BINDING
          value: "false"
        volumeMounts:
        - name: data
          mountPath: /var/lib/ldap
        - name: config
          mountPath: /etc/ldap/slapd.d
        - name: tls-certs
          mountPath: /import/certs
          readOnly: true
        livenessProbe:
          tcpSocket:
            port: 1389
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          exec:
            command:
            - ldapsearch
            - -x
            - -H
            - ldap://localhost:1389
            - -b
            - dc=example,dc=com
            - -LLL
          initialDelaySeconds: 20
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
      volumes:
      - name: tls-certs
        secret:
          secretName: openldap-tls-secret
          defaultMode: 0640
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: standard  # Adjust to your storage class
      resources:
        requests:
          storage: 10Gi
  - metadata:
      name: config
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: standard  # Adjust to your storage class
      resources:
        requests:
          storage: 1Gi
```

## Operations

### Deployment Commands

```bash
# Deploy everything
kubectl apply -f openldap-namespace.yaml
kubectl apply -f openldap-secrets.yaml
kubectl apply -f openldap-certificate.yaml  # If using cert-manager
kubectl apply -f openldap-statefulset.yaml

# Check status
kubectl get pods -n openldap
kubectl get pvc -n openldap
kubectl get certificates -n openldap  # If using cert-manager
kubectl logs -n openldap openldap-0

# Watch deployment
kubectl get pods -n openldap -w
```

### Testing Connection

#### From Within Cluster

```bash
kubectl run -it --rm ldap-test --image=debian:trixie-slim --restart=Never -n openldap -- bash
apt-get update && apt-get install -y ldap-utils
ldapsearch -x -H ldap://openldap.openldap.svc.cluster.local:1389 \
  -b "dc=example,dc=com" -D "cn=admin,dc=example,dc=com" -w admin_password
```

#### From Local Machine (Port Forward)

```bash
# Port-forward for local testing
kubectl port-forward -n openldap svc/openldap 1389:1389

# Test connection
ldapsearch -x -H ldap://localhost:1389 -b "dc=example,dc=com" \
  -D "cn=admin,dc=example,dc=com" -w admin_password
```

#### Testing LDAPS

```bash
# Port-forward LDAPS
kubectl port-forward -n openldap svc/openldap 1636:1636

# Test LDAPS connection
ldapsearch -x -H ldaps://localhost:1636 -b "dc=example,dc=com" \
  -D "cn=admin,dc=example,dc=com" -w admin_password
```

### Backup and Restore

#### Backup

```bash
# Create a backup
kubectl exec -n openldap openldap-0 -- \
  slapcat -b "dc=example,dc=com" > backup-$(date +%Y%m%d).ldif

# Backup to PVC
kubectl exec -n openldap openldap-0 -- \
  slapcat -b "dc=example,dc=com" -l /var/lib/ldap/backup.ldif
```

#### Automated Backup with CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: openldap-backup
  namespace: openldap
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: garthako/openldap:latest
            command:
            - /bin/sh
            - -c
            - |
              slapcat -b "dc=example,dc=com" > /backup/backup-$(date +%Y%m%d-%H%M%S).ldif
              # Keep only last 7 days
              find /backup -name "backup-*.ldif" -mtime +7 -delete
            volumeMounts:
            - name: backup
              mountPath: /backup
            - name: data
              mountPath: /var/lib/ldap
              readOnly: true
          restartPolicy: OnFailure
          volumes:
          - name: backup
            persistentVolumeClaim:
              claimName: openldap-backup
          - name: data
            persistentVolumeClaim:
              claimName: data-openldap-0
              readOnly: true
```

#### Restore

```bash
# Restore from backup
kubectl exec -i -n openldap openldap-0 -- \
  ldapadd -x -D "cn=admin,dc=example,dc=com" -w admin_password \
  < backup-20241011.ldif
```

### Scaling Considerations

For high availability, you'll need to configure LDAP replication manually:

```bash
# This image doesn't support automatic replication setup
# You'll need to configure it via LDIF files or manual configuration
```

## Troubleshooting

### Pod Not Starting

```bash
kubectl describe pod -n openldap openldap-0
kubectl logs -n openldap openldap-0
kubectl logs -n openldap openldap-0 --previous  # Previous container logs
```

### PVC Issues

```bash
kubectl get pvc -n openldap
kubectl describe pvc -n openldap data-openldap-0
kubectl get events -n openldap --sort-by='.lastTimestamp'
```

### Certificate Issues

```bash
# Check certificate status
kubectl get certificate -n openldap
kubectl describe certificate -n openldap openldap-tls

# Check certificate secret
kubectl get secret -n openldap openldap-tls-secret
kubectl describe secret -n openldap openldap-tls-secret

# View certificate details
kubectl get secret -n openldap openldap-tls-secret -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

### Connection Issues

```bash
# Check service endpoints
kubectl get endpoints -n openldap openldap

# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup openldap.openldap.svc.cluster.local

# Check network policies
kubectl get networkpolicies -n openldap
```

### Permission Issues

```bash
# Check pod security context
kubectl get pod -n openldap openldap-0 -o jsonpath='{.spec.securityContext}'

# Check volume permissions
kubectl exec -n openldap openldap-0 -- ls -la /var/lib/ldap
kubectl exec -n openldap openldap-0 -- ls -la /etc/ldap/slapd.d
```

### Traefik-Specific Issues

```bash
# Check Traefik logs
kubectl logs -n traefik -l app.kubernetes.io/name=traefik

# Check IngressRouteTCP status
kubectl describe ingressroutetcp -n openldap ldap-ingress

# Verify certificate
kubectl get certificate -n openldap ldap-tls
kubectl describe certificate -n openldap ldap-tls
```

## Kubernetes-Specific Considerations

1. **Storage Class**: Ensure your cluster has a suitable StorageClass for persistent volumes
2. **Resource Limits**: Adjust CPU/memory based on your LDAP load
3. **Network Policies**: Consider implementing NetworkPolicies to restrict access
4. **Pod Security**: The container runs as non-root (UID 1001) and is compatible with restricted PSPs/PSAs
5. **Scaling**: For multi-replica setups, configure LDAP replication manually
6. **Backup Strategy**: Implement regular backups using CronJobs
7. **Certificate Rotation**: cert-manager handles automatic renewal
8. **Monitoring**: Consider adding Prometheus metrics exporters
9. **High Availability**: Use anti-affinity rules for multi-replica deployments
10. **Security**: Use NetworkPolicies to restrict traffic between Traefik and OpenLDAP when using TLS termination

## Security Best Practices

1. **Use Secrets**: Never hardcode passwords in manifests
2. **Enable TLS**: Always use TLS for production deployments
3. **Restrict Access**: Use NetworkPolicies to limit access
4. **Regular Updates**: Keep the image and certificates up to date
5. **Audit Logs**: Enable and monitor LDAP audit logs
6. **Backup Encryption**: Encrypt backups at rest
7. **RBAC**: Implement proper Kubernetes RBAC for OpenLDAP resources
8. **Pod Security**: Use Pod Security Standards (restricted profile)

## Additional Resources

- [OpenLDAP Documentation](https://www.openldap.org/doc/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Kubernetes StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)