# GitHub Workflows and Scripts

This directory contains GitHub Actions workflows and supporting scripts for the repository.

## ArgoCD Path Management

### Overview

ArgoCD Application manifests need their `spec.source.path` fields to match their file locations in the repository. This ensures proper GitOps deployment.

### Files

- **workflows/validate-argocd-paths.yml** - GitHub Actions workflow that validates paths
- **scripts/validate-argocd-paths.sh** - Validation script that checks path correctness
- **../fix-argocd-paths.sh** - Script to fix incorrect paths (located at repo root)

### Validation Workflow

The `validate-argocd-paths.yml` workflow runs automatically:

- **On Pull Requests**: When any `app-of-apps.yaml` or `application.yaml` file changes
- **On Push to main**: When changes are merged to the main branch

#### What it checks

1. **app-of-apps.yaml files**: Ensures `spec.source.path` points to the bundle directory
   ```yaml
   # File: ocp/inference-nim/bundles/app-of-apps.yaml
   spec:
     source:
       path: ocp/inference-nim/bundles  # Must match file location
   ```

2. **application.yaml files (single-source)**: Ensures `spec.source.path` points to the component directory
   ```yaml
   # File: ocp/inference-nim/bundles/001-nfd-ocp-olm/application.yaml
   spec:
     source:
       path: ocp/inference-nim/bundles/001-nfd-ocp-olm  # Must match file location
   ```

3. **application.yaml files (multi-source)**: Ensures `$values` references match the component directory
   ```yaml
   # File: ocp/inference-nim/bundles/007-k8s-nim-operator-ocp/application.yaml
   spec:
     sources:
       - chart: k8s-nim-operator
         helm:
           valueFiles:
             - $values/ocp/inference-nim/bundles/007-k8s-nim-operator-ocp/values.yaml
   ```

### Manual Validation

Run the validation script locally:

```bash
# From repository root
.github/scripts/validate-argocd-paths.sh
```

### Fixing Invalid Paths

If validation fails, use the fix script:

```bash
# Fix paths for a specific bundle
./fix-argocd-paths.sh ocp/inference-nim/bundles

# Preview changes first (dry-run)
./fix-argocd-paths.sh ocp/inference-nim/bundles --dry-run
```

The fix script updates:
- `app-of-apps.yaml` - Updates parent application path
- All `application.yaml` files - Updates component paths (both single and multi-source)

### Workflow Behavior

**On Success**: Workflow passes silently

**On Failure**: 
- Workflow fails with exit code 1
- Detailed error messages show which files have incorrect paths
- For PRs: A comment is posted with fix instructions

### Example Workflow Run

```
✓ PASS: ./ocp/inference-nim/bundles/app-of-apps.yaml
✓ PASS: ./ocp/inference-nim/bundles/001-nfd-ocp-olm/application.yaml
✓ PASS: ./ocp/inference-nim/bundles/002-nfd-ocp/application.yaml
...
✓ All paths are valid!
```

### Troubleshooting

**Validation fails after generating a bundle with `aicr`**

The `aicr bundle` command doesn't currently support setting the path (only `--repo` for repository URL). After generating a bundle, run the fix script:

```bash
aicr bundle --recipe recipe.yaml --output ./bundles --deployer argocd \
  --repo https://github.com/aicatalyst-team/aicr-example-deployments.git

./fix-argocd-paths.sh bundles
```

**Script reports missing `app-of-apps.yaml`**

Ensure you're providing the full path to the bundle directory (the directory containing `app-of-apps.yaml`):

```bash
# Wrong
./fix-argocd-paths.sh ocp/inference-nim

# Correct
./fix-argocd-paths.sh ocp/inference-nim/bundles
```
