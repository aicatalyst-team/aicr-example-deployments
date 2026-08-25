# Argo CD Deployment Bundle

Bundler Version: 0.19.0
Recipe Version: 0.19.0

## Overview

This bundle contains Argo CD Application manifests for deploying NVIDIA AI Cluster Runtime components using the App of Apps pattern.

## Components

The following components are included in deployment order:

| Component | Type | Version | Sync Wave | Namespace |
|-----------|------|---------|-----------|-----------|
| nfd-ocp-olm | Local chart | - | 1 | openshift-nfd |
| nfd-ocp | Local chart | - | 5 | openshift-nfd |
| cert-manager-ocp-olm | Local chart | - | 9 | cert-manager-operator |
| cert-manager-ocp | Local chart | - | 13 | cert-manager-operator |
| gpu-operator-ocp-olm | Local chart | - | 9 | gpu-operator |
| gpu-operator-ocp | Local chart | - | 13 | gpu-operator |
| k8s-nim-operator-ocp | Helm | 3.1.0 | 17 | nvidia-nim |
| k8s-nim-operator-ocp-post | Local chart | - | 18 | nvidia-nim |
| network-operator-ocp-olm | Local chart | - | 9 | nvidia-network-operator |
| network-operator-ocp | Local chart | - | 13 | nvidia-network-operator |
| nvidia-dra-driver-gpu-ocp-pre | Local chart | - | 16 | nvidia-dra-driver |
| nvidia-dra-driver-gpu-ocp | Helm | 0.4.1 | 17 | nvidia-dra-driver |
| prometheus-adapter-ocp-pre | Local chart | - | 0 | monitoring |
| prometheus-adapter-ocp | Helm | 5.3.0 | 1 | monitoring |
| prometheus-adapter-ocp-post | Local chart | - | 2 | monitoring |

## Prerequisites

- Kubernetes cluster with Argo CD installed
- Argo CD CLI (`argocd`) configured
- Git repository for storing these manifests
- kubectl configured with cluster access

## Deployment Steps

### 1. Prepare Git Repository

Push this bundle to your GitOps repository:

```bash
cd <bundle-directory>
git init
git add .
git commit -m "Add NVIDIA AI Cluster Runtime manifests"
git remote add origin YOUR_REPO_URL
git push -u origin main
```

### 2. Update Repository URL

`repoURL` is baked into both `app-of-apps.yaml` *and* every per-component
`NNN-<component>/application.yaml` (path-based child Applications inherit
the bundle's repo URL — Argo CD does not propagate the parent's `repoURL`
to children). Update all of them in one pass:

```bash
# Update repoURL across the parent and every per-component application.yaml
find . -name 'application.yaml' -o -name 'app-of-apps.yaml' \
  | xargs sed -i 's|https://github.com/YOUR-ORG/YOUR-REPO.git|YOUR_ACTUAL_REPO_URL|g'
```

To avoid the rewrite, regenerate the bundle with `--repo` so the URL is
populated at bundle time:

```bash
aicr bundle --deployer argocd --repo YOUR_ACTUAL_REPO_URL ...
```

### 3. Apply App of Apps

```bash
kubectl apply -f app-of-apps.yaml
```

### 4. Monitor Deployment

```bash
# Watch application sync status
argocd app list

# Get detailed status for a specific application
argocd app get nvidia-stack

# Watch sync progress
argocd app sync nvidia-stack --watch
```

## Directory Structure

Each `NNN-<component>/` folder is one of two kinds, distinguished by the
presence of `Chart.yaml`. KindUpstreamHelm folders (no `Chart.yaml`) carry
just `values.yaml` + `application.yaml` — the Application is multi-source
(upstream Helm repo + your git repo for values). KindLocalHelm folders
(`Chart.yaml` + `templates/`) carry the wrapped chart bytes plus a
path-based single-source `application.yaml`.

```text
<bundle-directory>/
├── app-of-apps.yaml           # Parent application
├── README.md                  # This file
├── 001-nfd-ocp-olm/
│   ├── Chart.yaml             # Wrapped local chart
│   ├── templates/             # Rendered manifests
│   ├── values.yaml            # Static values
│   └── application.yaml       # Path-based Application (sync-wave: 1)
├── 002-nfd-ocp/
│   ├── Chart.yaml             # Wrapped local chart
│   ├── templates/             # Rendered manifests
│   ├── values.yaml            # Static values
│   └── application.yaml       # Path-based Application (sync-wave: 5)
├── 003-cert-manager-ocp-olm/
│   ├── Chart.yaml             # Wrapped local chart
│   ├── templates/             # Rendered manifests
│   ├── values.yaml            # Static values
│   └── application.yaml       # Path-based Application (sync-wave: 9)
├── 004-cert-manager-ocp/
│   ├── Chart.yaml             # Wrapped local chart
│   ├── templates/             # Rendered manifests
│   ├── values.yaml            # Static values
│   └── application.yaml       # Path-based Application (sync-wave: 13)
├── 005-gpu-operator-ocp-olm/
│   ├── Chart.yaml             # Wrapped local chart
│   ├── templates/             # Rendered manifests
│   ├── values.yaml            # Static values
│   └── application.yaml       # Path-based Application (sync-wave: 9)
├── 006-gpu-operator-ocp/
│   ├── Chart.yaml             # Wrapped local chart
│   ├── templates/             # Rendered manifests
│   ├── values.yaml            # Static values
│   └── application.yaml       # Path-based Application (sync-wave: 13)
├── 007-k8s-nim-operator-ocp/
│   ├── values.yaml            # Static values (multi-source helm.valueFiles)
│   └── application.yaml       # Multi-source Application (sync-wave: 17)
├── 008-k8s-nim-operator-ocp-post/
│   ├── Chart.yaml             # Wrapped local chart
│   ├── templates/             # Rendered manifests
│   ├── values.yaml            # Static values
│   └── application.yaml       # Path-based Application (sync-wave: 18)
├── 009-network-operator-ocp-olm/
│   ├── Chart.yaml             # Wrapped local chart
│   ├── templates/             # Rendered manifests
│   ├── values.yaml            # Static values
│   └── application.yaml       # Path-based Application (sync-wave: 9)
├── 010-network-operator-ocp/
│   ├── Chart.yaml             # Wrapped local chart
│   ├── templates/             # Rendered manifests
│   ├── values.yaml            # Static values
│   └── application.yaml       # Path-based Application (sync-wave: 13)
├── 011-nvidia-dra-driver-gpu-ocp-pre/
│   ├── Chart.yaml             # Wrapped local chart
│   ├── templates/             # Rendered manifests
│   ├── values.yaml            # Static values
│   └── application.yaml       # Path-based Application (sync-wave: 16)
├── 012-nvidia-dra-driver-gpu-ocp/
│   ├── values.yaml            # Static values (multi-source helm.valueFiles)
│   └── application.yaml       # Multi-source Application (sync-wave: 17)
├── 013-prometheus-adapter-ocp-pre/
│   ├── Chart.yaml             # Wrapped local chart
│   ├── templates/             # Rendered manifests
│   ├── values.yaml            # Static values
│   └── application.yaml       # Path-based Application (sync-wave: 0)
├── 014-prometheus-adapter-ocp/
│   ├── values.yaml            # Static values (multi-source helm.valueFiles)
│   └── application.yaml       # Multi-source Application (sync-wave: 1)
├── 015-prometheus-adapter-ocp-post/
│   ├── Chart.yaml             # Wrapped local chart
│   ├── templates/             # Rendered manifests
│   ├── values.yaml            # Static values
│   └── application.yaml       # Path-based Application (sync-wave: 2)
```

`--dynamic` is not supported with `--deployer argocd` — use `--deployer
argocd-helm` for install-time values. The helm-deployer files
(`install.sh`, `upstream.env`, `cluster-values.yaml`) are intentionally
omitted; Argo's repo-server never consumes them.

## Sync Waves

Components are deployed in order using Argo CD sync-waves:
- **Wave 1**: nfd-ocp-olm
- **Wave 5**: nfd-ocp
- **Wave 9**: cert-manager-ocp-olm
- **Wave 13**: cert-manager-ocp
- **Wave 9**: gpu-operator-ocp-olm
- **Wave 13**: gpu-operator-ocp
- **Wave 17**: k8s-nim-operator-ocp
- **Wave 18**: k8s-nim-operator-ocp-post
- **Wave 9**: network-operator-ocp-olm
- **Wave 13**: network-operator-ocp
- **Wave 16**: nvidia-dra-driver-gpu-ocp-pre
- **Wave 17**: nvidia-dra-driver-gpu-ocp
- **Wave 0**: prometheus-adapter-ocp-pre
- **Wave 1**: prometheus-adapter-ocp
- **Wave 2**: prometheus-adapter-ocp-post

## Customization

### Modifying Values

Edit the `values.yaml` file in each Helm component directory to customize the deployment.

### Changing Deployment Order

Modify the `sync-wave` annotation in each `application.yaml` to change deployment order.

## Troubleshooting

### Application Not Syncing

```bash
# Check application status
argocd app get <app-name>

# Force sync
argocd app sync <app-name> --force

# View application logs
argocd app logs <app-name>
```

### Resource Conflicts

If resources already exist, you may need to adopt them:

```bash
argocd app sync <app-name> --replace
```

## References

- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [App of Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
