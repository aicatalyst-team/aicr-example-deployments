# AICR Example Deployments

Example Deployments created by Nvidia's [AI Cluster Runtime](https://docs.nvidia.com/aicr).

AICR is a tool for creating configurations for AI stacks across a variety of cloud service providers.

This repo is about experimenting with its support for OpenShift Container Platform (OCP).

See the demo video in the AI Catalyst Platform Team drive at [aicr-demo-aug26.mp4](https://drive.google.com/file/d/1VgnHxtbDtqzzbLTE0XDd_JRs9vG1Seey/view?usp=drive_link).

See also the [executive summary](https://docs.google.com/document/d/1fs9rPXT7CF5xcSUzIS7Y9cDF6XhGdpRWYA63V56Iswc/edit?usp=drive_link).

## AICR Recipes

AICR Recipes can be created by giving arguments to the `aicr recipe` command and the tool will find the closest recipe template.

To see a list of all current `recipe` templates for OCP "service" use:

```bash
aicr recipe list --service ocp
```

For example to create a `recipe` for inference with NIM use:

```bash
aicr recipe --service ocp --intent inference --platform nim  --output ocp/inference-nim/recipe-ocp-nim.yaml
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

## Configuring Argo CD


If Argo CD is not already on the cluster install it through the OpenShift Console or with:

```bash
oc apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-gitops-operator
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-gitops-operator
  namespace: openshift-gitops-operator
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-gitops-operator
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

### ArgoCD permissions

As ArgoCD tries to install artefacts in to various namespaces, the default permissions its service account has will not be enough.

Grant Argo the Cluster Admin role, or give it more fine grained permissions.

To give it `cluster-admin` (not recommended for production systems) use:

```
oc adm policy add-cluster-role-to-user cluster-admin \
  system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller
```

### Argo CD Management Inferface

The route to the Argo CD Management interfaces should be available through

```bash
oc -n openshift-gitops get route
```

You can login with user `admin` and get the password from:

```bash
oc -n openshift-gitops get secret openshift-gitops-cluster -o yaml | yq '.data."admin.password"' | base64 -d
```

### Argo CLI

You should be able to connect to Argo with the [Argo CD CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/) like:

```bash
ARGOCD_ROUTE=<route from above>
ARGOCD_PASSWORD=<password from above>
argocd login https://$ARGOCD_ROUTE --insecure --username admin --password $ARGOCD_PASSWORD
```

> If this doesn't work, try port forwarding the gitops server on port 8080 and use the url `localhost:8080`

At this stage you should be able to list apps, but the list will be empty:

```bash
argocd app list
NAME  CLUSTER  NAMESPACE  PROJECT  STATUS  HEALTH  SYNCPOLICY  CONDITIONS  REPO  PATH  TARGET
```

Add the repo that was given in the `aicr bumdle` command above:

```bash
argocd repo add git@github.com:aicatalyst-team/aicr-example-deployments.git --insecure-ignore-host-key --ssh-private-key-path ~/.ssh/id_ecdsa
```

> Correct for your location for your Private SSH key

## Apply the configuration

As Argo is fully setup now, you can continue from step #3 in the generated README.md of the project [e.g. README.md](./ocp/inference-nim/bundles/README.md).

## AICR Validate

To validate against an openshift cluster, you will need to create a service account in the aicr-validation namespace:

```bash
# Create the service account (if it doesn't exist)
oc create serviceaccount aicr-privileged -n aicr-validation

# Grant the privileged SCC to this service account
oc adm policy add-scc-to-user privileged -z aicr-privileged -n aicr-validation
```

Then you can proceed with the validation:

```bash
aicr validate --recipe ocp/inference-nim/recipe-ocp-nim.yaml --service-account-name aicr-privileged --output ocp/inference-nim/validator-results-crc.json
```

> This will require a GPU by default. Most tests will fail if your cluster doesn't have one.