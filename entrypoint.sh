#!/bin/bash
set -e  # Exit on error

# ============================================================================
# OpenLDAP Docker Entrypoint Script
# ============================================================================
# This script handles first-run initialization and normal starts for OpenLDAP
# running as non-privileged user (ldapprivless, UID 1001)
#
# Maintainer: Mario Enrico Ragucci (ghmer) <openldap@r5i.xyz>
# Repository: https://github.com/ghmer/openldap-container
# License: MIT
# ============================================================================

# ----------------------------------------------------------------------------
# Cleanup Handler
# ----------------------------------------------------------------------------

# Trap handler for unified temporary file cleanup
cleanup_temp_files() {
    rm -f /tmp/config_root.ldif
    rm -f /tmp/frontend.ldif
    rm -f /tmp/configdb.ldif
    rm -f /tmp/config_pw.ldif
    rm -f /tmp/database_modify.ldif
    rm -f /tmp/database.ldif
    rm -f /tmp/admin_pw.ldif
    rm -f /tmp/base.ldif
    rm -f /tmp/tls_config.ldif
    rm -f /tmp/disable_anon.ldif
    rm -f /tmp/enable_exop.ldif
}

# Set trap to cleanup on exit
trap cleanup_temp_files EXIT

# ----------------------------------------------------------------------------
# Error Handling Functions
# ----------------------------------------------------------------------------

fatal_error() {
    echo "FATAL ERROR: $1" >&2
    exit 1
}

warn() {
    echo "WARNING: $1" >&2
}

log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $1"
}

require_readable_file() {
    local path="$1"

    if [ ! -f "$path" ]; then
        fatal_error "Required file not found: $path"
    fi

    if [ ! -r "$path" ]; then
        fatal_error "Required file not readable by $(id -u):$(id -g): $path"
    fi
}

require_writable_dir() {
    local path="$1"

    if [ ! -d "$path" ]; then
        fatal_error "Required directory not found: $path"
    fi

    if [ ! -w "$path" ] || [ ! -x "$path" ]; then
        fatal_error "Required directory not writable/executable by $(id -u):$(id -g): $path"
    fi
}

verify_runtime_paths() {
    log "Verifying runtime directory permissions..."

    require_writable_dir "/etc/ldap/slapd.d"
    require_writable_dir "/var/lib/ldap"
    require_writable_dir "/var/run/slapd"

    if [ "$LDAP_ENABLE_TLS" = "true" ]; then
        require_readable_file "$LDAP_TLS_CERT_FILE"
        require_readable_file "$LDAP_TLS_KEY_FILE"

        if [ -n "$LDAP_TLS_CA_FILE" ]; then
            require_readable_file "$LDAP_TLS_CA_FILE"
        fi
    fi

    log "Runtime directory permissions verified"
}

has_existing_ldap_data() {
    # Check for actual LDAP database files, not just any files
    # Ignore lost+found (filesystem metadata) and .state (our tracking file)
    if [ -f "/var/lib/ldap/data.mdb" ] ; then
        return 0
    fi

    return 1
}


# ----------------------------------------------------------------------------
# Environment Variables Setup
# ----------------------------------------------------------------------------

# Set defaults for optional variables
LDAP_PORT="${LDAP_PORT:-1389}"
LDAPS_PORT="${LDAPS_PORT:-1636}"
LDAP_SCHEMA_DIRECTORY="${LDAP_SCHEMA_DIRECTORY:-/import/schema}"
LDAP_LDIF_DATA_DIRECTORY="${LDAP_LDIF_DATA_DIRECTORY:-/import/ldif}"
LDAP_ENABLE_TLS="${LDAP_ENABLE_TLS:-false}"
LDAP_TLS_VERIFY_CLIENT="${LDAP_TLS_VERIFY_CLIENT:-try}"
LDAP_ALLOW_ANON_BINDING="${LDAP_ALLOW_ANON_BINDING:-true}"

# ----------------------------------------------------------------------------
# Validation Functions
# ----------------------------------------------------------------------------

validate_required_vars() {
    local errors=0
    
    # Check required variables
    if [ -z "$LDAP_BASE_DN" ]; then
        echo "ERROR: LDAP_BASE_DN not set" >&2
        errors=$((errors+1))
    fi
    
    if [ -z "$LDAP_ADMIN_USER" ]; then
        echo "ERROR: LDAP_ADMIN_USER not set" >&2
        errors=$((errors+1))
    fi
    
    if [ -z "$LDAP_ADMIN_PW" ]; then
        echo "ERROR: LDAP_ADMIN_PW not set" >&2
        errors=$((errors+1))
    fi
    
    if [ -z "$LDAP_CONFIG_ADMIN_PW" ]; then
        echo "ERROR: LDAP_CONFIG_ADMIN_PW not set" >&2
        errors=$((errors+1))
    fi
    
    return $errors
}

validate_dn_formats() {
    local errors=0
    
    # Validate DN format
    if [ -n "$LDAP_BASE_DN" ]; then
        echo "$LDAP_BASE_DN" | grep -qE '^(dc|o|ou)=[^,]+(,(dc|o|ou)=[^,]+)*$' || {
            echo "ERROR: LDAP_BASE_DN format invalid (must be like dc=example,dc=com)" >&2
            errors=$((errors+1))
        }
    fi
    
    # Validate RDN format
    if [ -n "$LDAP_ADMIN_USER" ]; then
        echo "$LDAP_ADMIN_USER" | grep -qE '^(cn|uid)=[^,]+$' || {
            echo "ERROR: LDAP_ADMIN_USER format invalid (must be like cn=admin)" >&2
            errors=$((errors+1))
        }
    fi
    
    return $errors
}

validate_boolean_options() {
    local errors=0
    
    # Validate TLS configuration if enabled
    if [ "$LDAP_ENABLE_TLS" = "true" ]; then
        if [ -z "$LDAP_TLS_CERT_FILE" ]; then
            echo "ERROR: LDAP_TLS_CERT_FILE required when TLS enabled" >&2
            errors=$((errors+1))
        fi
        
        if [ -z "$LDAP_TLS_KEY_FILE" ]; then
            echo "ERROR: LDAP_TLS_KEY_FILE required when TLS enabled" >&2
            errors=$((errors+1))
        fi
        
        # Note: TLS file existence validation is handled by verify_runtime_paths()
        # to avoid duplication. This was previously duplicated in lines 157-185.
        
        # Validate TLS verify client value
        case "$LDAP_TLS_VERIFY_CLIENT" in
            never|allow|try|demand) ;;
            *) 
                echo "ERROR: LDAP_TLS_VERIFY_CLIENT must be: never, allow, try, or demand" >&2
                errors=$((errors+1))
                ;;
        esac
    fi
    
    # Validate anonymous binding value
    case "$LDAP_ALLOW_ANON_BINDING" in
        true|false|"") ;;
        *) 
            echo "ERROR: LDAP_ALLOW_ANON_BINDING must be true or false" >&2
            errors=$((errors+1))
            ;;
    esac
    
    return $errors
}

validate_environment() {
    log "Validating environment variables..."
    local errors=0
    
    validate_required_vars || errors=$((errors+$?))
    validate_dn_formats || errors=$((errors+$?))
    validate_boolean_options || errors=$((errors+$?))
    
    if [ $errors -gt 0 ]; then
        fatal_error "Environment validation failed with $errors error(s)"
    fi
    
    log "Environment validation successful"
}

# ----------------------------------------------------------------------------
# Database Initialization Functions
# ----------------------------------------------------------------------------

clean_database() {
    log "Cleaning database directory..."
    rm -rf /var/lib/ldap/*
    
    # Verify cleanup
    if [ "$(ls -A /var/lib/ldap 2>/dev/null)" ]; then
        fatal_error "Failed to clean database directory"
    fi
    
    log "Database directory cleaned"
}

# Consolidated config initialization function
# Merges the functionality of initialize_config() and ensure_config_structure()
initialize_config_database() {
    log "Initializing config database..."
    
    local config_root="/etc/ldap/slapd.d/cn=config.ldif"
    local config_dir="/etc/ldap/slapd.d/cn=config"

    # Ensure config directory exists
    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir"
    fi

    # Check if config root exists
    if [ ! -f "$config_root" ]; then
        # First, try to copy from preserved default config
        if [ -d "/etc/ldap/slapd.d.default" ] && [ "$(ls -A /etc/ldap/slapd.d.default 2>/dev/null)" ]; then
            log "Copying default config from /etc/ldap/slapd.d.default..."
            cp -r /etc/ldap/slapd.d.default/* /etc/ldap/slapd.d/
            log "Default config copied successfully"
        # Fallback: Try to generate from slapd.conf if available
        elif [ -f "/etc/ldap/slapd.conf" ]; then
            if ! slaptest -f /etc/ldap/slapd.conf -F /etc/ldap/slapd.d 2>/dev/null; then
                warn "Could not generate config from slapd.conf, will create minimal config"
            else
                log "Generated cn=config tree from slapd.conf"
            fi
        else
            fatal_error "No default config or slapd.conf found."
        fi
    fi
    
    log "Config database initialized"
}

set_config_password() {
    log "Setting config admin password..."
    
    # Generate password hash
    local HASH=$(slappasswd -s "$LDAP_CONFIG_ADMIN_PW")
    
    # Create LDIF for password change
    cat > /tmp/config_pw.ldif <<EOF
dn: olcDatabase={0}config,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $HASH
EOF
    
    # Apply via offline mode
    slapmodify -F /etc/ldap/slapd.d -n 0 -l /tmp/config_pw.ldif || \
        fatal_error "Failed to set config admin password"
    
    log "Config admin password set"
}

create_database() {
    log "Creating database for $LDAP_BASE_DN..."

    local config_dir="/etc/ldap/slapd.d/cn=config"
    local target="${config_dir}/olcDatabase={1}mdb.ldif"

    if [ -f "$target" ]; then
        log "Updating existing database config entry"
        cat > /tmp/database_modify.ldif <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcDbDirectory
olcDbDirectory: /var/lib/ldap
-
replace: olcSuffix
olcSuffix: $LDAP_BASE_DN
-
replace: olcRootDN
olcRootDN: ${LDAP_ADMIN_USER},${LDAP_BASE_DN}
-
replace: olcDbIndex
olcDbIndex: objectClass eq
olcDbIndex: cn,uid eq
olcDbIndex: uidNumber,gidNumber eq
olcDbIndex: member,memberUid eq
-
replace: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by self write by anonymous auth by * none
olcAccess: {1}to dn.base="" by * read
olcAccess: {2}to * by self write by * none
EOF

        if ! slapmodify -F /etc/ldap/slapd.d -n 0 -l /tmp/database_modify.ldif; then
            fatal_error "Failed to update existing database entry"
        fi

        rm -f /tmp/database_modify.ldif
        log "Database entry updated"
        return 0
    fi

    log "Creating new database config entry"
    cat > /tmp/database.ldif <<EOF
dn: olcDatabase={1}mdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcMdbConfig
olcDatabase: {1}mdb
olcDbDirectory: /var/lib/ldap
olcSuffix: $LDAP_BASE_DN
olcRootDN: ${LDAP_ADMIN_USER},${LDAP_BASE_DN}
olcDbIndex: objectClass eq
olcDbIndex: cn,uid eq
olcDbIndex: uidNumber,gidNumber eq
olcDbIndex: member,memberUid eq
olcAccess: {0}to attrs=userPassword,shadowLastChange by self write by anonymous auth by * none
olcAccess: {1}to dn.base="" by * read
olcAccess: {2}to * by self write by * none
EOF

    if ! slapadd -F /etc/ldap/slapd.d -n 0 -l /tmp/database.ldif; then
        fatal_error "Failed to create database"
    fi

    log "Database created"
}

set_admin_password() {
    log "Setting admin password..."
    
    local HASH=$(slappasswd -s "$LDAP_ADMIN_PW")
    
    cat > /tmp/admin_pw.ldif <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $HASH
EOF
    
    slapmodify -F /etc/ldap/slapd.d -n 0 -l /tmp/admin_pw.ldif || \
        fatal_error "Failed to set admin password"
    
    log "Admin password set"
}

create_base_entry() {
    log "Creating base DN entry..."
    
    # Extract DC components
    local DC_PARTS=$(echo "$LDAP_BASE_DN" | sed 's/dc=//g' | sed 's/,/ /g')
    local FIRST_DC=$(echo "$DC_PARTS" | awk '{print $1}')
    local ORG_NAME=$(echo "$DC_PARTS" | sed 's/ /./g')
    
    cat > /tmp/base.ldif <<EOF
dn: $LDAP_BASE_DN
objectClass: top
objectClass: dcObject
objectClass: organization
dc: $FIRST_DC
o: $ORG_NAME
EOF
    
    slapadd -b "$LDAP_BASE_DN" -l /tmp/base.ldif -F /etc/ldap/slapd.d || \
        fatal_error "Failed to create base DN entry"
    
    log "Base DN entry created"
}

# ----------------------------------------------------------------------------
# TLS Configuration
# ----------------------------------------------------------------------------

configure_tls() {
    if [ "$LDAP_ENABLE_TLS" != "true" ]; then
        log "TLS disabled, skipping TLS configuration"
        return 0
    fi

    log "Configuring TLS/SSL..."

    cat > /tmp/tls_config.ldif <<EOF
dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: $LDAP_TLS_CERT_FILE
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: $LDAP_TLS_KEY_FILE
EOF

    if [ -n "$LDAP_TLS_CA_FILE" ]; then
        cat >> /tmp/tls_config.ldif <<EOF
-
replace: olcTLSCACertificateFile
olcTLSCACertificateFile: $LDAP_TLS_CA_FILE
EOF
    fi

    cat >> /tmp/tls_config.ldif <<EOF
-
replace: olcTLSVerifyClient
olcTLSVerifyClient: ${LDAP_TLS_VERIFY_CLIENT}
EOF

    slapmodify -F /etc/ldap/slapd.d -n 0 -l /tmp/tls_config.ldif || {
        fatal_error "Failed to configure TLS"
    }

    log "TLS configuration complete"
}

# ----------------------------------------------------------------------------
# Anonymous Binding Configuration
# ----------------------------------------------------------------------------

configure_anonymous_binding() {
    if [ "$LDAP_ALLOW_ANON_BINDING" != "false" ]; then
        log "Anonymous binding enabled (default)"
        return 0
    fi
    
    log "Disabling anonymous binding..."
    
    # Create LDIF to modify access rules
    cat > /tmp/disable_anon.ldif <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by self write by anonymous auth by * none
olcAccess: {1}to dn.base="" by * read
olcAccess: {2}to * by self write by users read by * none
EOF

    slapmodify -F /etc/ldap/slapd.d -n 0 -l /tmp/disable_anon.ldif || {
        warn "Failed to disable anonymous binding, continuing with defaults"
    }
    
    log "Anonymous binding disabled"
}

# ----------------------------------------------------------------------------
# Password Modify Extended Operation Configuration
# ----------------------------------------------------------------------------

enable_password_modify_exop() {
    log "Enabling LDAPv3 Password Modify Extended Operation..."
    
    # Check if ppolicy module is already loaded
    if slapcat -F /etc/ldap/slapd.d -n 0 2>/dev/null | grep -q "olcModuleLoad.*ppolicy"; then
        log "Password Modify Extended Operation already enabled"
        return 0
    fi
    
    # Create LDIF to load ppolicy module
    cat > /tmp/enable_exop.ldif <<EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: ppolicy
EOF

    # Try to modify existing module entry first
    if slapmodify -F /etc/ldap/slapd.d -n 0 -l /tmp/enable_exop.ldif 2>/dev/null; then
        log "Password Modify Extended Operation enabled via module modification"
        return 0
    fi
    
    # If modification failed, try to add new module entry
    cat > /tmp/enable_exop.ldif <<EOF
dn: cn=module{0},cn=config
objectClass: olcModuleList
cn: module{0}
olcModuleLoad: ppolicy
EOF

    if slapadd -F /etc/ldap/slapd.d -n 0 -l /tmp/enable_exop.ldif 2>/dev/null; then
        log "Password Modify Extended Operation enabled via new module entry"
        return 0
    fi
    
    warn "Could not enable Password Modify Extended Operation, continuing anyway"
}

# ----------------------------------------------------------------------------
# Schema and Data Loading with Hash Tracking
# ----------------------------------------------------------------------------

# State file to track imported files
STATE_FILE="/var/lib/ldap/.state"

# Calculate SHA256 hash of a file
calculate_hash() {
    local file="$1"
    sha256sum "$file" | awk '{print $1}'
}

# Check if file was already imported with same hash
is_already_imported() {
    local file="$1"
    local current_hash=$(calculate_hash "$file")
    local filename=$(basename "$file")
    
    # Create state file if it doesn't exist
    [ -f "$STATE_FILE" ] || touch "$STATE_FILE"
    
    # Check if hash exists in state file
    if grep -q "^${filename}:${current_hash}$" "$STATE_FILE" 2>/dev/null; then
        return 0  # Already imported
    fi
    
    return 1  # Not imported or hash changed
}

# Mark file as imported by storing its hash
mark_as_imported() {
    local file="$1"
    local current_hash=$(calculate_hash "$file")
    local filename=$(basename "$file")
    
    # Remove old entry for this file if exists
    if [ -f "$STATE_FILE" ]; then
        sed -i "/^${filename}:/d" "$STATE_FILE"
    fi
    
    # Add new entry
    echo "${filename}:${current_hash}" >> "$STATE_FILE"
}

load_schemas() {
    log "Loading custom schemas..."
    
    if [ -d "$LDAP_SCHEMA_DIRECTORY" ]; then
        # Load schemas in alphabetical order
        for schema in "$LDAP_SCHEMA_DIRECTORY"/*.ldif; do
            [ -f "$schema" ] || continue
            
            if is_already_imported "$schema"; then
                log "Skipping schema (already imported): $(basename $schema)"
                continue
            fi
            
            log "Loading schema: $(basename $schema)"
            if slapadd -F /etc/ldap/slapd.d -n 0 -l "$schema"; then
                mark_as_imported "$schema"
                log "Successfully imported schema: $(basename $schema)"
            else
                warn "Failed to load schema $schema, continuing..."
            fi
        done
    else
        log "No custom schema directory found at $LDAP_SCHEMA_DIRECTORY"
    fi
}

import_ldif_files() {
    log "Importing LDIF files..."
    
    if [ -d "$LDAP_LDIF_DATA_DIRECTORY" ] && [ "$(ls -A $LDAP_LDIF_DATA_DIRECTORY/*.ldif 2>/dev/null)" ]; then
        # Import files in alphabetical order using offline tool
        for ldif in "$LDAP_LDIF_DATA_DIRECTORY"/*.ldif; do
            [ -f "$ldif" ] || continue
            
            if is_already_imported "$ldif"; then
                log "Skipping LDIF (already imported): $(basename $ldif)"
                continue
            fi
            
            log "Importing: $(basename $ldif)"
            # -c: continue on errors (skip duplicates like base DN)
            # -w: write operational attributes (entryUUID, timestamps, etc.)
            if slapadd -c -w -b "$LDAP_BASE_DN" -l "$ldif" -F /etc/ldap/slapd.d; then
                mark_as_imported "$ldif"
                log "Successfully imported LDIF: $(basename $ldif)"
            else
                warn "Failed to import $ldif, continuing..."
            fi
        done
    else
        log "No LDIF files found in $LDAP_LDIF_DATA_DIRECTORY"
    fi
}

# Note: Lines 666-668 from original script removed - "Marker File Management" section
# was empty with no implementation and therefore unreachable/unused code.

# ----------------------------------------------------------------------------
# Normal Start Function
# ----------------------------------------------------------------------------

normal_start() {
    log "Starting slapd (already initialized)..."
    
    # Verify critical files exist
    if [ ! -f "/etc/ldap/slapd.d/cn=config.ldif" ]; then
        fatal_error "Config database missing"
    fi
    
    if [ ! -d "/var/lib/ldap" ]; then
        fatal_error "Database directory missing"
    fi
    
    # Build service URLs based on TLS configuration
    local SERVICES="ldapi:/// ldap://:${LDAP_PORT}/"
    
    if [ "$LDAP_ENABLE_TLS" = "true" ]; then
        SERVICES="${SERVICES} ldaps://:${LDAPS_PORT}/"
    fi
    
    log "Starting slapd with services: $SERVICES"
    
    # Start slapd in foreground
    exec /usr/sbin/slapd \
        -u ldapprivless \
        -g ldapprivless \
        -h "$SERVICES" \
        -F /etc/ldap/slapd.d \
        -d 256
}

# ----------------------------------------------------------------------------
# First Run Initialization
# ----------------------------------------------------------------------------

first_run_initialization() {
    log "=== First Run Initialization ==="
    
    clean_database
    initialize_config_database
    set_config_password
    create_database
    set_admin_password
    create_base_entry
    enable_password_modify_exop

    log "=== Initialization Complete ==="
}

apply_configuration() {
    log "=== Applying Config Changes From Env Variables ==="

    configure_tls
    configure_anonymous_binding
    load_schemas
    import_ldif_files

    log "=== Configuration Complete ==="
}

# ============================================================================
# Main Execution
# ============================================================================

log "OpenLDAP Docker Entrypoint Starting..."

# Validate environment
validate_environment

# Verify runtime permissions before proceeding
verify_runtime_paths

# Check initialization state
if has_existing_ldap_data; then
    log "Existing LDAP configuration/data detected, starting without initialization"
    apply_configuration
    normal_start
else
    log "No LDAP configuration/data detected, performing first-run initialization"
    first_run_initialization
    apply_configuration
    normal_start
fi