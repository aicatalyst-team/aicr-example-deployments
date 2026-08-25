# AICR Example Deployments

Example Deployments created by Nvidia's [AI Cluster Runtime](https://docs.nvidia.com/aicr).

AICR is a tool for creating configurations for AI stacks across a variety of cloud service providers.

This repo is about experimenting with its support for OpenShift Container Platform (OCP).

## AICR Recipes

AICR Recipes can be created by giving arguments to the `aicr recipe` command and the tool will find the closest recipe template.

To see a list of all current `recipe` templates for OCP "service" use:

```bash
aicr recipe list --service ocp
```

For example to create a `recipe` for inference with NIM use:

```bash
aicr recipe --service ocp --intent training --platform nim  --output ocp/inference-nim/recipe-ocp-nim.yaml
```

## AICR Bundles

To create a bundle a deployer must be chosen. The default is `helm`, but here we focus on `argocd`.

For example to create an argocd `bundle` for the `recipe` given above you could use:

```bash
aicr bundle --recipe ocp/inference-nim/recipe-ocp-nim.yaml --deployer argocd --output ocp/inference-nim/bundles --repo https://github.com/aicatalyst-team/aicr-example-deployments.git
```

> While it's possible to set the `repoURL` in generated ArgoCD files through this `repo` argument, it's not possible to set the path (needed for shared repos) - see below.


### Argo CD deployment paths

Because this repo is the location of many Argo CD deployments, so the `path` should be set to the folder the bundle resides in for `app-of-apps.yaml` and all sub-directories.

Use the `fix-argocd-path.sh` script to fix this path after creation of a bundle through `aicr bundle` command.

```
./fix-argocd-paths.sh ocp/inference-nim/bundles/
```

> The CI in this repo checks that the path has been set.