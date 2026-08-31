#!/usr/bin/env bash
# Fix ArgoCD Application paths in aicr-generated bundles
#
# Usage: ./fix-argocd-paths.sh <bundle-directory> [--dry-run]
#
# Example: ./fix-argocd-paths.sh ocp/inference-nim/bundles
#
# This script updates the 'path' field in app-of-apps.yaml and all child
# application.yaml files to use the full repository path instead of relative paths.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 <bundle-directory> [--dry-run] [--namespace <namespace>]"
    echo ""
    echo "Arguments:"
    echo "  bundle-directory       Path to the bundle directory (e.g., ocp/inference-nim/bundles)"
    echo "  --dry-run             Show what would be changed without modifying files"
    echo "  --namespace <value>   Set metadata.namespace in application files (default: openshift-gitops)"
    echo ""
    echo "Example:"
    echo "  $0 ocp/inference-nim/bundles"
    echo "  $0 ocp/inference-nim/bundles --dry-run"
    echo "  $0 ocp/inference-nim/bundles --namespace argocd"
    exit 1
}

# Check arguments
if [ $# -lt 1 ]; then
    echo -e "${RED}Error: Missing required argument${NC}" >&2
    usage
fi

BUNDLE_DIR="$1"
DRY_RUN=false
NAMESPACE="openshift-gitops"

# Parse optional arguments
shift
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --namespace)
            if [ -z "$2" ] || [[ "$2" == --* ]]; then
                echo -e "${RED}Error: --namespace requires a value${NC}" >&2
                usage
            fi
            NAMESPACE="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Error: Unknown option '$1'${NC}" >&2
            usage
            ;;
    esac
done

# Validate bundle directory exists
if [ ! -d "$BUNDLE_DIR" ]; then
    echo -e "${RED}Error: Directory '$BUNDLE_DIR' does not exist${NC}" >&2
    exit 1
fi

# Convert to absolute path for clarity, but use the original relative path for the YAML
BUNDLE_DIR_CLEAN="${BUNDLE_DIR%/}"  # Remove trailing slash if present

# Validate app-of-apps.yaml exists (ensures user provided correct bundle directory)
APP_OF_APPS="$BUNDLE_DIR_CLEAN/app-of-apps.yaml"
if [ ! -f "$APP_OF_APPS" ]; then
    echo -e "${RED}Error: app-of-apps.yaml not found in '$BUNDLE_DIR_CLEAN'${NC}" >&2
    echo -e "${RED}Please provide the full path to the bundle directory${NC}" >&2
    echo -e "${RED}(the directory containing app-of-apps.yaml)${NC}" >&2
    exit 1
fi

echo "================================================================="
echo "ArgoCD Path Fixer"
echo "================================================================="
echo "Bundle directory: $BUNDLE_DIR_CLEAN"
echo "Target namespace: $NAMESPACE"
echo "Dry run: $DRY_RUN"
echo ""

# Function to update a file with sed (for path updates)
update_file_sed() {
    local file="$1"
    local pattern="$2"
    local replacement="$3"
    local description="$4"

    if [ ! -f "$file" ]; then
        echo -e "${YELLOW}⚠ Skipping: $file (not found)${NC}"
        return
    fi

    # Check if pattern exists in file
    if ! grep -q "$pattern" "$file"; then
        echo -e "${YELLOW}⚠ Skipping: $file (pattern not found)${NC}"
        return
    fi

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY RUN] Would update: $file${NC}"
        echo "  Change: $description"
        grep "$pattern" "$file" | head -1 | sed 's/^/  Before: /'
        echo "  After:  $(grep "$pattern" "$file" | head -1)" | sed -E "$replacement"
    else
        echo -e "${GREEN}✓ Updating: $file${NC}"
        echo "  Change: $description"
        # Use -i with empty string for portability (works on both GNU and BSD sed)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS (BSD sed)
            sed -i '' -E "$replacement" "$file"
        else
            # Linux (GNU sed)
            sed -i -E "$replacement" "$file"
        fi
    fi
}

# Function to update YAML field with yq
update_yaml_field() {
    local file="$1"
    local yq_path="$2"
    local new_value="$3"
    local description="$4"
    local allow_create="${5:-false}"  # Optional: allow creating field if it doesn't exist

    if [ ! -f "$file" ]; then
        echo -e "${YELLOW}⚠ Skipping: $file (not found)${NC}"
        return
    fi

    # Check if yq is installed
    if ! command -v yq &> /dev/null; then
        echo -e "${RED}Error: yq is not installed. Please install it: https://github.com/mikefarah/yq${NC}" >&2
        exit 1
    fi

    # Get current value
    local current_value
    current_value=$(yq eval "$yq_path" "$file" 2>/dev/null)

    if [ "$current_value" == "null" ] || [ -z "$current_value" ]; then
        if [ "$allow_create" != "true" ]; then
            echo -e "${YELLOW}⚠ Skipping: $file (field $yq_path not found)${NC}"
            return
        fi
        current_value="<not set>"
    fi

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY RUN] Would update: $file${NC}"
        echo "  Change: $description"
    else
        echo -e "${GREEN}✓ Updating: $file${NC}"
        echo "  Change: $description"
        yq eval -i "$yq_path = \"$new_value\"" "$file"
    fi
}

# Update app-of-apps.yaml
echo "Processing app-of-apps.yaml..."
echo "-----------------------------------------------------------------"
update_file_sed \
    "$APP_OF_APPS" \
    "path: \." \
    "s|(path: )\.|\\1$BUNDLE_DIR_CLEAN|" \
    "path: . → path: $BUNDLE_DIR_CLEAN"

# Update namespace in app-of-apps.yaml metadata
update_yaml_field \
    "$APP_OF_APPS" \
    ".metadata.namespace" \
    "$NAMESPACE" \
    "metadata.namespace → $NAMESPACE"

# Special case: app-of-apps.yaml destination namespace should always be openshift-gitops
# (where the child Application resources will be created)
update_yaml_field \
    "$APP_OF_APPS" \
    ".spec.destination.namespace" \
    "openshift-gitops" \
    "spec.destination.namespace → openshift-gitops (child Applications target)"
echo ""

# Update all child application.yaml files
echo "Processing child applications..."
echo "-----------------------------------------------------------------"

# Find all application.yaml files in subdirectories (not the app-of-apps.yaml)
while IFS= read -r -d '' app_file; do
    # Get the component folder name (e.g., "001-nfd-ocp-olm")
    component_folder=$(basename "$(dirname "$app_file")")

    # Check if this is a multi-source application with ref: values
    if grep -q "ref: values" "$app_file"; then
        # Pattern 2: Multi-source applications with "$values/<folder>/values.yaml"
        # Ensure $values references have the full path
        if grep -q "\$values/$component_folder/values.yaml" "$app_file"; then
            update_file_sed \
                "$app_file" \
                "\$values/$component_folder/values.yaml" \
                "s|(\\\$values/)($component_folder/values.yaml)|\\1$BUNDLE_DIR_CLEAN/\\2|" \
                "\$values/$component_folder/values.yaml → \$values/$BUNDLE_DIR_CLEAN/$component_folder/values.yaml"
        fi
    else
        # Pattern 1: Local chart applications with "path: <folder>"
        if grep -q "path: $component_folder" "$app_file"; then
            update_file_sed \
                "$app_file" \
                "path: $component_folder" \
                "s|(path: )($component_folder)|\\1$BUNDLE_DIR_CLEAN/\\2|" \
                "path: $component_folder → path: $BUNDLE_DIR_CLEAN/$component_folder"
        fi
    fi

    # Update namespace in child application
    update_yaml_field \
        "$app_file" \
        ".metadata.namespace" \
        "$NAMESPACE" \
        "metadata.namespace → $NAMESPACE"
done < <(find "$BUNDLE_DIR_CLEAN" -mindepth 2 -name "application.yaml" -print0)

echo ""

# Special cases
echo "Processing special cases..."
echo "-----------------------------------------------------------------"

# Fix prometheus-adapter RBAC ServiceAccount name
PROM_ADAPTER_RBAC="$BUNDLE_DIR_CLEAN/015-prometheus-adapter-ocp-post/templates/rbac.yaml"
if [ -f "$PROM_ADAPTER_RBAC" ]; then
    update_yaml_field \
        "$PROM_ADAPTER_RBAC" \
        ".subjects[0].name" \
        "prometheus-adapter-ocp" \
        "subjects[0].name → prometheus-adapter-ocp (ServiceAccount reference)" \
        "true"
else
    echo -e "${YELLOW}⚠ Skipping: prometheus-adapter RBAC file not found${NC}"
fi

# Fix network-operator subscription name and channel
NETWORK_OP_SUB="$BUNDLE_DIR_CLEAN/009-network-operator-ocp-olm/templates/subscription.yaml"
if [ -f "$NETWORK_OP_SUB" ]; then
    update_yaml_field \
        "$NETWORK_OP_SUB" \
        ".metadata.name" \
        "nvidia-network-operator" \
        "metadata.name → nvidia-network-operator (Subscription resource name)" \
        "false"

    update_yaml_field \
        "$NETWORK_OP_SUB" \
        ".spec.name" \
        "nvidia-network-operator" \
        "spec.name → nvidia-network-operator (Subscription operator name)" \
        "false"

    update_yaml_field \
        "$NETWORK_OP_SUB" \
        ".spec.channel" \
        "stable" \
        "spec.channel → stable (Subscription channel)" \
        "false"
else
    echo -e "${YELLOW}⚠ Skipping: network-operator subscription file not found${NC}"
fi

# Fix network-operator OperatorGroup spec
NETWORK_OP_GROUP="$BUNDLE_DIR_CLEAN/009-network-operator-ocp-olm/templates/operatorgroup.yaml"
if [ -f "$NETWORK_OP_GROUP" ]; then
    # Check if spec.targetNamespaces already exists
    if ! yq eval '.spec.targetNamespaces' "$NETWORK_OP_GROUP" 2>/dev/null | grep -q 'nvidia-network-operator'; then
        if [ "$DRY_RUN" = true ]; then
            echo -e "${YELLOW}[DRY RUN] Would update: $NETWORK_OP_GROUP${NC}"
            echo "  Change: Add spec.targetNamespaces → [nvidia-network-operator]"
        else
            echo -e "${GREEN}✓ Updating: $NETWORK_OP_GROUP${NC}"
            echo "  Change: Add spec.targetNamespaces → [nvidia-network-operator]"
            yq eval -i '.spec.targetNamespaces = ["nvidia-network-operator"]' "$NETWORK_OP_GROUP"
        fi
    else
        echo -e "${YELLOW}⚠ Skipping: $NETWORK_OP_GROUP (spec.targetNamespaces already set)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Skipping: network-operator OperatorGroup file not found${NC}"
fi

echo ""

# Regenerate checksums
if [ "$DRY_RUN" = false ]; then
    echo "Regenerating checksums..."
    echo "-----------------------------------------------------------------"
    CHECKSUMS_FILE="$BUNDLE_DIR_CLEAN/checksums.txt"

    if command -v sha256sum &> /dev/null; then
        # Change to bundle directory to get relative paths
        pushd "$BUNDLE_DIR_CLEAN" > /dev/null

        # Generate checksums for all files except checksums.txt itself
        find . -type f ! -name "checksums.txt" ! -path "./.git/*" -print0 | \
            sort -z | \
            xargs -0 sha256sum | \
            sed 's|^\([^ ]*\)  \./|\1  |' > checksums.txt

        popd > /dev/null

        echo -e "${GREEN}✓ Updated: $CHECKSUMS_FILE${NC}"
        echo "  $(wc -l < "$CHECKSUMS_FILE") file checksums regenerated"
    else
        echo -e "${YELLOW}⚠ Warning: sha256sum not found, skipping checksum update${NC}"
    fi
    echo ""
fi

echo "================================================================="
if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}DRY RUN COMPLETE - No files were modified${NC}"
    echo "Run without --dry-run to apply changes"
else
    echo -e "${GREEN}COMPLETE - All paths updated successfully${NC}"
fi
echo "================================================================="
