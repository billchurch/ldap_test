#!/bin/bash
set -e

# ---------------------------------------------------------------------------
# Shared entrypoint for all LDAP test containers (Debian, Rocky, Ubuntu)
#
# Generates /etc/nslcd.conf from environment variables at container start,
# then launches nslcd and sshd.  The nslcd gid is auto-detected because
# Debian/Ubuntu use group "nslcd" while Rocky/RHEL use group "ldap".
# ---------------------------------------------------------------------------

# --- Determine the correct group for nslcd ----------------------------------
if getent group nslcd >/dev/null 2>&1; then
    NSLCD_GID="nslcd"
elif getent group ldap >/dev/null 2>&1; then
    NSLCD_GID="ldap"
else
    echo "ERROR: Neither 'nslcd' nor 'ldap' group found" >&2
    exit 1
fi

# --- Generate /etc/nslcd.conf from environment variables --------------------
cat > /etc/nslcd.conf <<EOF
uid nslcd
gid ${NSLCD_GID}

uri ${LDAP_URI:-ldap://192.168.10.116}
base ${LDAP_BASE:-DC=mydomain,DC=local}
binddn ${LDAP_BINDDN:-CN=Administrator,CN=Users,DC=mydomain,DC=local}
bindpw ${LDAP_BINDPW:-Password123}

ldap_version 3
referrals no
scope sub

filter passwd (&(objectClass=user)(sAMAccountName=*))
map passwd uid sAMAccountName
map passwd uidNumber uidNumber
map passwd gidNumber gidNumber
map passwd homeDirectory unixHomeDirectory
map passwd loginShell loginShell
map passwd gecos displayName
EOF

chmod 600 /etc/nslcd.conf

# --- Set root password to a random value (use `docker exec` for root access) -
echo "root:$(head -c 32 /dev/urandom | base64)" | chpasswd

# --- Start nslcd ------------------------------------------------------------
nslcd

# --- Start sshd in foreground -----------------------------------------------
exec /usr/sbin/sshd -D -e
