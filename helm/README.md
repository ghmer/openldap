# OpenLDAP Helm Chart

A Helm chart for deploying OpenLDAP directory service on Kubernetes.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PV provisioner support in the underlying infrastructure (if persistence is enabled)
- Traefik ingress controller (if IngressRouteTCP is enabled)
- cert-manager (if Certificate resource is enabled)

## Installation

### Install from local chart

```bash
helm install openldap ./helm
```

### Install with custom values

```bash
helm install openldap ./helm -f custom-values.yaml
```

### Install in a specific namespace

```bash
helm install openldap ./helm --namespace openldap --create-namespace
```

## Configuration

The following table lists the configurable parameters and their default values.

### Global Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `namespaceCreate` | Create namespace | `true` |
| `namespace` | Namespace name | `openldap` |
| `replicaCount` | Number of replicas | `1` |

### Image Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Image repository | `garthako/openldap` |
| `image.tag` | Image tag | `v2.6` |
| `image.pullPolicy` | Image pull policy | `Always` |

### LDAP Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ldap.baseDN` | LDAP base DN | `dc=example,dc=local` |
| `ldap.domain` | LDAP domain | `ldap.example.local` |
| `ldap.organisation` | Organization name | `Example Organization` |
| `ldap.adminUser` | Admin user DN | `cn=admin` |
| `ldap.port` | LDAP port | `1389` |
| `ldap.enableTLS` | Enable TLS | `false` |
| `ldap.allowAnonymousBinding` | Allow anonymous binding | `false` |

### Secrets

| Parameter | Description | Default | Base64 encoded | 
|-----------|-------------|---------|
| `secrets.adminPassword` | Admin password | `adminPassword` | `YWRtaW5QYXNzd29yZAo=` |
| `secrets.configAdminPassword` | Config admin password | `ConfigAdminPassword` | `Q29uZmlnQWRtaW5QYXNzd29yZAo=` |

**Important:** Change these passwords before deploying to production!

### Persistence

| Parameter | Description | Default |
|-----------|-------------|---------|
| `persistence.data.enabled` | Enable data persistence | `true` |
| `persistence.data.size` | Data volume size | `512Mi` |
| `persistence.data.storageClass` | Storage class | `""` |
| `persistence.data.accessMode` | Access mode | `ReadWriteOnce` |
| `persistence.config.enabled` | Enable config persistence | `true` |
| `persistence.config.size` | Config volume size | `128Mi` |
| `persistence.config.storageClass` | Storage class | `""` |
| `persistence.config.accessMode` | Access mode | `ReadWriteOnce` |

### Service

| Parameter | Description | Default |
|-----------|-------------|---------|
| `service.type` | Service type | `ClusterIP` |
| `service.port` | Service port | `389` |
| `service.targetPort` | Container port | `1389` |
| `service.sessionAffinity.enabled` | Enable session affinity | `true` |
| `service.sessionAffinity.timeoutSeconds` | Session timeout | `10800` |

### Ingress (Traefik)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingressRoute.enabled` | Enable IngressRouteTCP | `true` |
| `ingressRoute.entryPoints` | Entry points | `[ldaps]` |
| `ingressRoute.hosts` | Hostnames | See values.yaml |
| `ingressRoute.tls.secretName` | TLS secret name | `ldaps-cert-tls` |

### Certificate (cert-manager)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `certificate.enabled` | Enable Certificate resource | `true` |
| `certificate.secretName` | Secret name for certificate | `ldaps-cert-tls` |
| `certificate.issuerRef.name` | Issuer name | `letsencrypt-prod` |
| `certificate.issuerRef.kind` | Issuer kind | `ClusterIssuer` |
| `certificate.dnsNames` | DNS names | See values.yaml |
| `certificate.renewBefore` | Renew before expiry | `72h` |

### Resources

| Parameter | Description | Default |
|-----------|-------------|---------|
| `resources.requests.cpu` | CPU request | `10m` |
| `resources.requests.memory` | Memory request | `1Gi` |
| `resources.limits.cpu` | CPU limit | `50m` |
| `resources.limits.memory` | Memory limit | `2Gi` |

### Schemas and LDIF Data

| Parameter | Description | Default |
|-----------|-------------|---------|
| `schemas.enabled` | Enable custom schemas | `true` |
| `schemas.data` | Schema definitions | See values.yaml |
| `ldifData.enabled` | Enable LDIF data import | `true` |
| `ldifData.data` | LDIF entries | See values.yaml |

## Usage Examples

### Basic Installation

```bash
helm install openldap ./helm
```

### Custom LDAP Configuration

```yaml
# custom-values.yaml
ldap:
  baseDN: "dc=example,dc=com"
  domain: "ldap.example.com"
  organisation: "Example Organization"

secrets:
  adminPassword: "base64-encoded-password"
  configAdminPassword: "base64-encoded-password"
```

```bash
helm install openldap ./helm -f custom-values.yaml
```

### Disable Optional Features

```yaml
# minimal-values.yaml
ingressRoute:
  enabled: false

certificate:
  enabled: false

schemas:
  enabled: false

ldifData:
  enabled: false
```

```bash
helm install openldap ./helm -f minimal-values.yaml
```

### Using Different Storage Class

```yaml
# storage-values.yaml
persistence:
  data:
    storageClass: "fast-ssd"
  config:
    storageClass: "fast-ssd"
```

```bash
helm install openldap ./helm -f storage-values.yaml
```

## Upgrading

```bash
helm upgrade openldap ./helm
```

## Uninstalling

```bash
helm uninstall openldap
```

**Note:** PVCs are not automatically deleted. Delete them manually if needed:

```bash
kubectl delete pvc -n openldap openldap-data openldap-config
```

## Testing the Deployment

After installation, test the LDAP connection:

```bash
# Get the admin password
kubectl get secret -n openldap openldap-secrets -o jsonpath="{.data.LDAP_ADMIN_PW}" | base64 --decode

# Port forward to the service
kubectl port-forward -n openldap svc/openldap 1389:389

# Test LDAP search
ldapsearch -x -H ldap://localhost:1389 -b "dc=example,dc=local" -D "cn=admin,dc=example,dc=local" -W
```

## Troubleshooting

### Check pod status

```bash
kubectl get pods -n openldap
kubectl describe pod -n openldap <pod-name>
kubectl logs -n openldap <pod-name>
```

### Check PVC status

```bash
kubectl get pvc -n openldap
```

### Verify ConfigMaps and Secrets

```bash
kubectl get configmap -n openldap
kubectl get secret -n openldap
```

## Security Considerations

1. **Change default passwords** before deploying to production
2. The chart runs as non-root user (UID 1001)
3. Security contexts are enforced
4. Consider using external secret management solutions for production
5. Enable TLS for production deployments
6. Restrict anonymous binding in production

## License

MIT

## Maintainer

Mario Enrico Ragucci (ghmer)
- Email: openldap@r5i.xyz
- Repository: https://github.com/ghmer/openldap-container