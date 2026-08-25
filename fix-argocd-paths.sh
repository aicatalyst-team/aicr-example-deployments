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
    echo "Usage: $0 <bundle-directory> [--dry-run]"
    echo ""
    echo "Arguments:"
    echo "  bundle-directory  Path to the bundle directory (e.g., ocp/inference-nim/bundles)"
    echo "  --dry-run        Show what would be changed without modifying files"
    echo ""
    echo "Example:"
    echo "  $0 ocp/inference-nim/bundles"
    echo "  $0 ocp/inference-nim/bundles --dry-run"
    exit 1
}

# Check arguments
if [ $# -lt 1 ]; then
    echo -e "${RED}Error: Missing required argument${NC}" >&2
    usage
fi

BUNDLE_DIR="$1"
DRY_RUN=false

if [ $# -eq 2 ]; then
    if [ "$2" == "--dry-run" ]; then
        DRY_RUN=true
    else
        echo -e "${RED}Error: Unknown option '$2'${NC}" >&2
        usage
    fi
fi

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
echo "Dry run: $DRY_RUN"
echo ""

# Function to update a file
update_file() {
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
        echo "  After:  $(echo "$(grep "$pattern" "$file" | head -1)" | sed -E "$replacement")"
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

# Update app-of-apps.yaml
echo "Processing app-of-apps.yaml..."
echo "-----------------------------------------------------------------"
update_file \
    "$APP_OF_APPS" \
    "path: \." \
    "s|(path: )\.|\\1$BUNDLE_DIR_CLEAN|" \
    "path: . → path: $BUNDLE_DIR_CLEAN"
echo ""

# Update all child application.yaml files
echo "Processing child applications..."
echo "-----------------------------------------------------------------"

# Find all application.yaml files in subdirectories (not the app-of-apps.yaml)
while IFS= read -r -d '' app_file; do
    # Get the component folder name (e.g., "001-nfd-ocp-olm")
    component_folder=$(basename "$(dirname "$app_file")")

    # Pattern 1: Local chart applications with "path: <folder>"
    if grep -q "path: $component_folder" "$app_file"; then
        update_file \
            "$app_file" \
            "path: $component_folder" \
            "s|(path: )($component_folder)|\\1$BUNDLE_DIR_CLEAN/\\2|" \
            "path: $component_folder → path: $BUNDLE_DIR_CLEAN/$component_folder"
    fi

    # Pattern 2: Multi-source applications with "$values/<folder>/values.yaml"
    if grep -q "\$values/$component_folder/values.yaml" "$app_file"; then
        update_file \
            "$app_file" \
            "\$values/$component_folder/values.yaml" \
            "s|(\\\$values/)($component_folder/values.yaml)|\\1$BUNDLE_DIR_CLEAN/\\2|" \
            "\$values/$component_folder/values.yaml → \$values/$BUNDLE_DIR_CLEAN/$component_folder/values.yaml"
    fi
done < <(find "$BUNDLE_DIR_CLEAN" -mindepth 2 -name "application.yaml" -print0)

echo ""
echo "================================================================="
if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}DRY RUN COMPLETE - No files were modified${NC}"
    echo "Run without --dry-run to apply changes"
else
    echo -e "${GREEN}COMPLETE - All paths updated successfully${NC}"
fi
echo "================================================================="
