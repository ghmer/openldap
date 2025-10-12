# OpenLDAP Container Image

A privately-maintained OpenLDAP container image.

**Maintainer:** Mario Enrico Ragucci (ghmer) - [openldap@r5i.xyz](mailto:openldap@r5i.xyz)
**Repository:** [https://github.com/ghmer/openldap-container](https://github.com/ghmer/openldap-container)
**License:** MIT

**⚠️ WORK IN PROGRESS - NOT PRODUCTION READY**

This image is under development and definitely lacks reviews. Some functionality is still missing. Use at your own risk.

Its aim is to provide a container image that is kept up to date. It can be found in dockerhub: [garthako/openldap:latest](https://hub.docker.com/r/garthako/openldap)

## Quick Start

```bash
docker run -d \
  --name openldap \
  -p 1389:1389 \
  -e LDAP_BASE_DN="dc=example,dc=com" \
  -e LDAP_ADMIN_USER="cn=admin" \
  -e LDAP_ADMIN_PW="admin_password" \
  -e LDAP_CONFIG_ADMIN_PW="config_password" \
  garthako/openldap:latest
```

Test connection:
```bash
ldapsearch -x -H ldap://localhost:1389 -b "dc=example,dc=com" \
  -D "cn=admin,dc=example,dc=com" -w admin_password
```

## What's Included

- **Base**: Debian Trixie (slim)
- **User**: Non-root (UID 1001)
- **Ports**: 1389 (LDAP), 1636 (LDAPS)
- **Architectures**: amd64, arm64, arm/v7

## Configuration

### Required Environment Variables

| Variable | Example |
|----------|---------|
| `LDAP_BASE_DN` | `dc=example,dc=com` |
| `LDAP_ADMIN_USER` | `cn=admin` |
| `LDAP_ADMIN_PW` | `admin_password` |
| `LDAP_CONFIG_ADMIN_PW` | `config_password` |

### Optional Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `LDAP_ALLOW_ANON_BINDING` | `false` | Allow anonymous binds |
| `LDAP_ENABLE_TLS` | `false` | Enable LDAPS |
| `LDAP_TLS_CERT_FILE` | - | Path to TLS cert - required if `LDAP_ENABLE_TLS` is true |
| `LDAP_TLS_KEY_FILE` | - | Path to TLS key - required if `LDAP_ENABLE_TLS` is true |
| `LDAP_TLS_CA_FILE` | - | Path to CA cert - required if `LDAP_ENABLE_TLS` is true |
| `LDAPS_PORT` | `1636` | LDAPS port - required if `LDAP_ENABLE_TLS` is true |
| `LDAP_PORT` | `1389` | LDAP port |

## Docker Compose

### Basic Setup

```yaml
services:
  openldap:
    image: garthako/openldap:latest
    container_name: openldap
    environment:
      LDAP_BASE_DN: "dc=example,dc=com"
      LDAP_ADMIN_USER: "cn=admin"
      LDAP_ADMIN_PW: "admin_password"
      LDAP_CONFIG_ADMIN_PW: "config_password"
    ports:
      - "1389:1389"
    volumes:
      - ldap_data:/var/lib/ldap
      - ldap_config:/etc/ldap/slapd.d
    user: "1001:1001"
    ulimits:
      nofile: 1024
    restart: unless-stopped

volumes:
  ldap_data:
  ldap_config:
```

### Advanced Setup with TLS and Initial Data

```yaml
services:
  openldap:
    image: garthako/openldap:latest
    container_name: openldap
    environment:
      LDAP_BASE_DN: "dc=example,dc=com"
      LDAP_ADMIN_USER: "cn=admin"
      LDAP_ADMIN_PW: "admin_password"
      LDAP_CONFIG_ADMIN_PW: "config_password"
      LDAP_ENABLE_TLS: "true"
      LDAP_TLS_CERT_FILE: "/import/certs/server.crt"
      LDAP_TLS_KEY_FILE: "/import/certs/server.key"
      LDAP_TLS_CA_FILE: "/import/certs/ca.crt"
      LDAP_ALLOW_ANON_BINDING: "false"
    ports:
      - "1389:1389"
      - "1636:1636"
    volumes:
      - ldap_data:/var/lib/ldap
      - ldap_config:/etc/ldap/slapd.d
      - ./ldif:/import/ldif:ro
      - ./schema:/import/schema:ro
      - ./certs:/import/certs:ro
    user: "1001:1001"
    ulimits:
      nofile: 1024
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "ldapsearch", "-x", "-H", "ldap://localhost:1389", "-b", "dc=example,dc=com", "-LLL"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

volumes:
  ldap_data:
  ldap_config:
```

## Volumes

| Path | Purpose |
|------|---------|
| `/var/lib/ldap` | Database files |
| `/etc/ldap/slapd.d` | Configuration |
| `/import/ldif` | Initial LDIF files (optional) |
| `/import/schema` | Custom schemas (optional) |
| `/import/certs` | TLS certificates (optional) |

Volumes must be writable by UID 1001:
```bash
sudo chown -R 1001:1001 /path/to/volumes
```

## TLS/LDAPS

```bash
docker run -d \
  -p 1636:1636 \
  -e LDAP_ENABLE_TLS="true" \
  -e LDAP_TLS_CERT_FILE="/import/certs/server.crt" \
  -e LDAP_TLS_KEY_FILE="/import/certs/server.key" \
  -e LDAP_TLS_CA_FILE="/import/certs/ca.crt" \
  -v ./certs:/import/certs:ro \
  # ... other config
```

## Initial Data

Place LDIF files in `/import/ldif` - they're imported automatically on first run:

```bash
docker run -d \
  -v ./ldif:/import/ldif:ro \
  # ... other config
```

### Migration Steps

1. Backup from existing server:

- Get an ldif export of your data. Exported operational attributes will be imported, too.
- Get rid of the baseDN entry.
- Place the exported file into a folder `import-ldif`
- Place any schema extensions into a folder `import-schema`

2. Configure your container with same base DN

- Mount folders into place:
  - ./import-schema:/import/schema:ro
  - ./import-ldif:/import/ldif:ro

3. Start the container

Watch for log entries. 

## Troubleshooting

**Permission errors**: Ensure volumes owned by UID 1001
```bash
sudo chown -R 1001:1001 /path/to/volumes
```

**TLS errors**: Check cert permissions (readable by UID 1001)
```bash
chmod 644 server.crt ca.crt
chmod 600 server.key
```

**Connection refused**: Check logs
```bash
docker logs openldap
```

## Support

This is a private project without commercial support. Report issues on GitHub.

**Maintainer Contact:**
- GitHub: [@ghmer](https://github.com/ghmer)
- Email: openldap@r5i.xyz
- Repository: [https://github.com/ghmer/openldap-container](https://github.com/ghmer/openldap-container)

### We Need Your Help! 🙋

**Looking for volunteers to validate this OpenLDAP image.**

As this project is still in development, I am looking for community members to:

- **Test the image** in various environments and use cases
- **Validate functionality** against your specific LDAP requirements
- **Report bugs and issues** you encounter during testing
- **Share feedback** on configuration, documentation, and usability
- **Contribute improvements** through pull requests

**How to Help:**

1. Try the image in your development/testing environment
2. Test different configurations (TLS, custom schemas, LDIF imports, etc.)
3. Validate migration scenarios
4. Document your findings and report issues on GitHub
5. Share your use case and any missing features you identify

Your testing and feedback are much appreciated. Every contribution, whether it's a bug report, documentation improvement, or feature suggestion, helps the entire community.

**Get Started:** Pull the image, follow the Quick Start guide, and let us know how it works for you!
