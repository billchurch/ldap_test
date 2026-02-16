# GitHub Workflows Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Set up release-please for changelog/versioning and Docker multi-platform publish to GHCR with release notes.

**Architecture:** Two GitHub Actions workflows — release-please.yml (triggered on push to main) creates releases, docker-publish.yml (triggered on release published) builds 3 distro images for amd64+arm64 and updates release notes.

**Tech Stack:** GitHub Actions, googleapis/release-please-action@v4, docker/build-push-action, GHCR

---

### Task 1: Create release-please config files

**Files:**
- Create: `release-please-config.json`
- Create: `.release-please-manifest.json`
- Create: `version.txt`

**Step 1: Create `release-please-config.json`**

```json
{
  "packages": {
    ".": {
      "release-type": "simple",
      "bump-minor-pre-major": false,
      "bump-patch-for-minor-pre-major": false,
      "changelog-path": "CHANGELOG.md",
      "versioning": "default"
    }
  },
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json"
}
```

**Step 2: Create `.release-please-manifest.json`**

```json
{
  ".": "1.0.0"
}
```

**Step 3: Create `version.txt`**

```
1.0.0
```

**Step 4: Verify files are valid JSON**

Run: `python3 -c "import json; json.load(open('release-please-config.json')); json.load(open('.release-please-manifest.json')); print('OK')"`
Expected: `OK`

**Step 5: Commit**

```bash
git add release-please-config.json .release-please-manifest.json version.txt
git commit -m "chore: add release-please configuration with initial version 1.0.0"
```

---

### Task 2: Create release-please workflow

**Files:**
- Create: `.github/workflows/release-please.yml`

**Step 1: Create the workflow file**

```yaml
name: Release Please

on:
  push:
    branches:
      - main

permissions:
  contents: write
  pull-requests: write

jobs:
  release-please:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@v4
        with:
          config-file: release-please-config.json
          manifest-file: .release-please-manifest.json
```

**Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release-please.yml')); print('OK')"`
Expected: `OK`

**Step 3: Commit**

```bash
git add .github/workflows/release-please.yml
git commit -m "ci: add release-please workflow for automated releases"
```

---

### Task 3: Create Docker publish workflow — build job

**Files:**
- Create: `.github/workflows/docker-publish.yml`

**Step 1: Create the workflow with the build job**

```yaml
name: Docker Publish

on:
  release:
    types: [published]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

permissions:
  contents: write
  packages: write

jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        distro: [debian, rocky, ubuntu]
        include:
          - distro: debian
            is_default: true
          - distro: rocky
            is_default: false
          - distro: ubuntu
            is_default: false
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract version parts
        id: version
        run: |
          VERSION="${{ github.event.release.tag_name }}"
          VERSION="${VERSION#v}"
          MAJOR="${VERSION%%.*}"
          MINOR="${VERSION#*.}"
          MINOR="${MINOR%%.*}"
          echo "full=${VERSION}" >> "$GITHUB_OUTPUT"
          echo "major=${MAJOR}" >> "$GITHUB_OUTPUT"
          echo "minor=${MAJOR}.${MINOR}" >> "$GITHUB_OUTPUT"

      - name: Generate tags
        id: tags
        run: |
          IMAGE="${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}"
          IMAGE=$(echo "$IMAGE" | tr '[:upper:]' '[:lower:]')
          DISTRO="${{ matrix.distro }}"
          VERSION="${{ steps.version.outputs.full }}"
          MAJOR="${{ steps.version.outputs.major }}"
          MINOR="${{ steps.version.outputs.minor }}"

          TAGS="${IMAGE}:${DISTRO}"
          TAGS="${TAGS},${IMAGE}:${DISTRO}-${VERSION}"
          TAGS="${TAGS},${IMAGE}:${DISTRO}-${MINOR}"
          TAGS="${TAGS},${IMAGE}:${DISTRO}-${MAJOR}"

          if [ "${{ matrix.is_default }}" = "true" ]; then
            TAGS="${TAGS},${IMAGE}:latest"
            TAGS="${TAGS},${IMAGE}:${VERSION}"
            TAGS="${TAGS},${IMAGE}:${MINOR}"
            TAGS="${TAGS},${IMAGE}:${MAJOR}"
          fi

          echo "tags=${TAGS}" >> "$GITHUB_OUTPUT"

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          file: ${{ matrix.distro }}/Dockerfile
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ${{ steps.tags.outputs.tags }}
          cache-from: type=gha,scope=${{ matrix.distro }}
          cache-to: type=gha,mode=max,scope=${{ matrix.distro }}

  update-release-notes:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: Extract version
        id: version
        run: |
          VERSION="${{ github.event.release.tag_name }}"
          VERSION="${VERSION#v}"
          echo "full=${VERSION}" >> "$GITHUB_OUTPUT"

      - name: Update release notes with Docker info
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GH_REPO: ${{ github.repository }}
        run: |
          VERSION="${{ steps.version.outputs.full }}"
          IMAGE="ghcr.io/${{ github.repository }}"
          IMAGE=$(echo "$IMAGE" | tr '[:upper:]' '[:lower:]')
          TAG="${{ github.event.release.tag_name }}"

          MAJOR="${VERSION%%.*}"
          MINOR_PART="${VERSION#*.}"
          MINOR="${MAJOR}.${MINOR_PART%%.*}"

          EXISTING=$(gh release view "$TAG" --json body -q .body)

          DOCKER_NOTES=$(cat <<INNEREOF

          ---

          ## Docker Images

          This release is available as multi-platform Docker images (linux/amd64, linux/arm64):

          ### GitHub Container Registry

          **Default (Debian):**
          \`\`\`bash
          docker pull ${IMAGE}:latest
          docker pull ${IMAGE}:${VERSION}
          docker pull ${IMAGE}:${MINOR}
          docker pull ${IMAGE}:${MAJOR}
          \`\`\`

          **Debian:**
          \`\`\`bash
          docker pull ${IMAGE}:debian
          docker pull ${IMAGE}:debian-${VERSION}
          \`\`\`

          **Rocky Linux:**
          \`\`\`bash
          docker pull ${IMAGE}:rocky
          docker pull ${IMAGE}:rocky-${VERSION}
          \`\`\`

          **Ubuntu:**
          \`\`\`bash
          docker pull ${IMAGE}:ubuntu
          docker pull ${IMAGE}:ubuntu-${VERSION}
          \`\`\`

          **Links:**
          - [GitHub Container Registry](https://github.com/${{ github.repository }}/pkgs/container/${GITHUB_REPOSITORY#*/})
          INNEREOF
          )

          UPDATED_BODY="${EXISTING}${DOCKER_NOTES}"

          gh release edit "$TAG" --notes "$UPDATED_BODY"
```

**Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/docker-publish.yml')); print('OK')"`
Expected: `OK` (note: GitHub Actions expressions `${{ }}` are not valid YAML values, so this validates structure only)

**Step 3: Commit**

```bash
git add .github/workflows/docker-publish.yml
git commit -m "ci: add Docker multi-platform publish workflow with release notes"
```

---

### Task 4: Validate complete setup

**Step 1: Verify all new files exist**

Run: `ls -la release-please-config.json .release-please-manifest.json version.txt .github/workflows/release-please.yml .github/workflows/docker-publish.yml`
Expected: All 5 files listed

**Step 2: Verify no existing files were modified**

Run: `git diff HEAD~3 -- debian/Dockerfile rocky/Dockerfile ubuntu/Dockerfile docker-compose.yml shared/entrypoint.sh`
Expected: No output (no changes)

**Step 3: Review git log**

Run: `git log --oneline -5`
Expected: 3 new commits on top of existing work

**Step 4: Final commit (if any adjustments needed)**

No commit expected unless fixes are required.
