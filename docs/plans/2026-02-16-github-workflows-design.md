# GitHub Workflows Design: Release-Please + Docker Publish

**Date:** 2026-02-16
**Status:** Approved

## Goals

1. Maintain a changelog using Google release-please
2. Publish Docker containers to ghcr.io on release
3. Multi-platform images (linux/amd64, linux/arm64)
4. Mark releases as latest
5. Update release notes with Docker pull instructions after successful push

## Architecture: Two Workflows

### Workflow 1: release-please.yml

- **Trigger:** push to `main`
- **Action:** `googleapis/release-please-action@v4`
- **Release type:** `simple` (tracks version in `version.txt`)
- **Initial version:** `1.0.0`
- **Outputs:** Generates `CHANGELOG.md` from conventional commits, creates release PRs, publishes GitHub releases

### Workflow 2: docker-publish.yml

- **Trigger:** `release: published`
- **Job 1 — `build`:** Matrix over `[debian, rocky, ubuntu]`
  - QEMU + Buildx for multi-platform builds
  - GHCR login via `GITHUB_TOKEN`
  - Build context: repo root, Dockerfile path: `<distro>/Dockerfile`
  - Platforms: `linux/amd64,linux/arm64`
- **Job 2 — `update-release-notes`:** Runs after all builds succeed
  - Appends Docker pull instructions to the release body via `gh release edit`

## Image & Tag Scheme

Single image: `ghcr.io/billchurch/ldap_test`

| Distro | Tags |
|--------|------|
| debian (default) | `:latest`, `:X.Y.Z`, `:X.Y`, `:X`, `:debian`, `:debian-X.Y.Z`, `:debian-X.Y`, `:debian-X` |
| rocky | `:rocky`, `:rocky-X.Y.Z`, `:rocky-X.Y`, `:rocky-X` |
| ubuntu | `:ubuntu`, `:ubuntu-X.Y.Z`, `:ubuntu-X.Y`, `:ubuntu-X` |

## Release Notes Docker Section

After successful image push, the release body is updated to append:

```markdown
---

## Docker Images

This release is available as multi-platform Docker images (linux/amd64, linux/arm64):

### GitHub Container Registry

**Default (Debian):**
docker pull ghcr.io/billchurch/ldap_test:latest
docker pull ghcr.io/billchurch/ldap_test:X.Y.Z
docker pull ghcr.io/billchurch/ldap_test:X.Y
docker pull ghcr.io/billchurch/ldap_test:X

**Debian:**
docker pull ghcr.io/billchurch/ldap_test:debian
docker pull ghcr.io/billchurch/ldap_test:debian-X.Y.Z

**Rocky Linux:**
docker pull ghcr.io/billchurch/ldap_test:rocky
docker pull ghcr.io/billchurch/ldap_test:rocky-X.Y.Z

**Ubuntu:**
docker pull ghcr.io/billchurch/ldap_test:ubuntu
docker pull ghcr.io/billchurch/ldap_test:ubuntu-X.Y.Z

**Links:**
- [GitHub Container Registry](https://github.com/billchurch/ldap_test/pkgs/container/ldap_test)
```

## New Files

| File | Purpose |
|------|---------|
| `.github/workflows/release-please.yml` | Release-please automation |
| `.github/workflows/docker-publish.yml` | Docker build/push + release notes update |
| `release-please-config.json` | Release-please configuration |
| `.release-please-manifest.json` | Version tracking |
| `version.txt` | Simple version file (`1.0.0`) |

## Existing Files — No Changes

- Dockerfiles: no changes (build context set to repo root)
- `docker-compose.yml`: unchanged
- `shared/entrypoint.sh`: unchanged
- `.gitignore`: unchanged

## Prerequisites

- Conventional commits required going forward (e.g. `feat:`, `fix:`)
- `GITHUB_TOKEN` permissions: contents write, packages write (configured in workflow)
