# LDAP Proxy Authentication Test Suite

Docker-based test suite for validating LDAP proxy authentication across multiple Linux distributions. Spins up three containers — **Debian 12**, **Rocky Linux 9**, and **Ubuntu 24.04** — each configured with [nslcd](https://arthurdejong.org/nss-pam-ldapd/) to authenticate users against an LDAP proxy using ephemeral (temporary, single-use) passwords.

## How It Works

Each container runs `nslcd` + `sshd`. When a user SSHs in:

1. **nslcd** binds as a service account to search for the user's DN
2. **nslcd** opens a new connection and binds as the user DN with the supplied password
3. The **LDAP proxy** validates the credential (e.g., an ephemeral one-time password)
4. On success, SEARCH queries are proxied to the real Active Directory domain controller

This proves the LDAP proxy works end-to-end for external Linux clients across different distributions.

## Quick Start

```bash
# Clone and start all three containers
git clone <this-repo>
cd ldap_test

# (Optional) Customize configuration
cp .env.example .env
# Edit .env with your LDAP proxy address, base DN, bind credentials, etc.

# Build and start
docker compose up -d --build

# Verify containers are running
docker compose ps
```

## Configuration

All parameters are set via environment variables. Defaults are baked into `docker-compose.yml` for the lab environment — override them with a `.env` file or shell variables.

| Variable | Default | Description |
|---|---|---|
| `LDAP_URI` | `ldap://192.168.10.116` | LDAP proxy URI |
| `LDAP_BASE` | `DC=mydomain,DC=local` | Search base DN |
| `LDAP_BINDDN` | `CN=Administrator,CN=Users,...` | Service account DN for nslcd |
| `LDAP_BINDPW` | `Password123` | Service account password |

Override inline without a `.env` file:

```bash
LDAP_URI=ldap://10.0.0.50 LDAP_BASE=DC=corp,DC=example,DC=com docker compose up -d --build
```

## Testing

### SSH Ports

| Container | Distro | SSH Port |
|---|---|---|
| `ldap-test-debian` | Debian 12 | 2201 |
| `ldap-test-rocky` | Rocky Linux 9 | 2202 |
| `ldap-test-ubuntu` | Ubuntu 24.04 | 2203 |

### Test Workflow

1. **Generate an ephemeral credential** for your test user (method depends on your LDAP proxy)

2. **SSH to each container** using the ephemeral password:

   ```bash
   ssh -p 2201 joe.user@localhost   # Debian
   ssh -p 2202 joe.user@localhost   # Rocky
   ssh -p 2203 joe.user@localhost   # Ubuntu
   ```

3. **Verify user resolution** from inside the container:

   ```bash
   id joe.user
   getent passwd joe.user
   ```

4. **Manual LDAP testing** (all containers include `ldapsearch`):

   ```bash
   ldapsearch -x -H ldap://192.168.10.116 \
     -D "CN=joe user,CN=Users,DC=mydomain,DC=local" \
     -w "<ephemeral-password>" \
     -b "DC=mydomain,DC=local" "(sAMAccountName=joe.user)"
   ```

### Debug Access

Root SSH login is disabled. Use `docker exec` for root access:

```bash
docker exec -it ldap-test-debian bash
docker exec -it ldap-test-rocky bash
docker exec -it ldap-test-ubuntu bash
```

## Architecture

```
shared/entrypoint.sh    Shared entrypoint — generates nslcd.conf from env vars,
                        auto-detects gid (nslcd vs ldap), starts nslcd + sshd

debian/Dockerfile       Debian 12 (bookworm-slim)
rocky/Dockerfile        Rocky Linux 9
ubuntu/Dockerfile       Ubuntu 24.04

docker-compose.yml      Orchestrates all three with port mapping + env config
.env.example            Template for environment overrides
```

### What the Entrypoint Does

At container start, `shared/entrypoint.sh`:

1. Detects the correct nslcd group (`nslcd` on Debian/Ubuntu, `ldap` on Rocky)
2. Generates `/etc/nslcd.conf` from environment variables
3. Sets the root password to a random value (root SSH is disabled; use `docker exec`)
4. Starts `nslcd` (backgrounds itself)
5. Starts `sshd` in foreground

### Platform-Specific Notes

| Issue | Debian | Ubuntu | Rocky |
|---|---|---|---|
| **Packages** | `nslcd libpam-ldapd libnss-ldapd ldap-utils` | Same as Debian | `epel-release` + `nss-pam-ldapd openldap-clients` |
| **nslcd group** | `nslcd` | `nslcd` | `ldap` (GID 55) |
| **PAM LDAP module** | `pam_ldapd.so` (auto-configured by `libpam-ldapd`) | Same as Debian | `pam_ldap.so` (manually added to PAM stacks) |
| **pam_systemd.so** | Commented out (25s timeout fix) | Commented out (same issue) | Uses `-session` prefix (no fix needed) |
| **mkhomedir** | Appended to `common-session` | Same as Debian | Inserted into `system-auth` + `password-auth` |
| **SSH config** | `/etc/ssh/sshd_config` (sed) | Same as Debian | Drop-in: `/etc/ssh/sshd_config.d/50-ldap-test.conf` |
| **SSH host keys** | Generated at package install | Same as Debian | Explicit `ssh-keygen -A` required |

## Rebuilding

```bash
# Rebuild a single container
docker compose build debian
docker compose up -d debian

# Rebuild all from scratch (no cache)
docker compose build --no-cache
docker compose up -d

# Tear down everything
docker compose down
```

## AD User Requirements

LDAP users must have POSIX attributes set in Active Directory:

- `uidNumber` — unique numeric UID
- `gidNumber` — primary group GID
- `unixHomeDirectory` — e.g., `/home/joe.user`
- `loginShell` — e.g., `/bin/bash`
- `sAMAccountName` — used as the Linux username

## Troubleshooting

**nslcd won't start / "not a valid gid" error:**
Check that the entrypoint correctly detects the group. On Rocky, the group is `ldap`, not `nslcd`.

```bash
docker exec ldap-test-rocky getent group ldap
docker exec ldap-test-rocky getent group nslcd
```

**SSH login hangs for 25 seconds (Debian/Ubuntu):**
The `pam_systemd.so` fix may not have applied. Check:

```bash
docker exec ldap-test-debian grep pam_systemd /etc/pam.d/common-session
```

Lines should be commented out (`#`).

**"Permission denied" on SSH:**
- Verify the ephemeral credential hasn't expired
- Check nslcd can reach the LDAP proxy: `docker exec ldap-test-debian nslcd -d`
- Verify the user has POSIX attributes in AD

**User resolves but can't login:**
The LDAP proxy may be accepting the service account bind (search) but rejecting the user bind (auth). Check the proxy logs.

**Home directory not created:**
Verify `pam_mkhomedir.so` is in the PAM session stack:

```bash
# Debian/Ubuntu
docker exec ldap-test-debian grep mkhomedir /etc/pam.d/common-session

# Rocky
docker exec ldap-test-rocky grep mkhomedir /etc/pam.d/system-auth
```
