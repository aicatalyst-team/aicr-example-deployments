#!/usr/bin/env bash
# Validate ArgoCD Application paths match their file locations
#
# This script checks that spec.source.path (or $values references) match
# the directory containing the YAML file.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0

echo "================================================================="
echo "ArgoCD Application Path Validator"
echo "================================================================="
echo ""

# Check if yq is available
if ! command -v yq &> /dev/null; then
    echo -e "${RED}Error: yq is required but not installed${NC}" >&2
    echo "Install: https://github.com/mikefarah/yq" >&2
    exit 1
fi

# Function to validate any ArgoCD Application YAML
validate_argocd_app() {
    local file="$1"
    local dir
    dir=$(dirname "$file")
    local expected_path="${dir#./}"  # Remove leading ./

    # Try to get single-source path
    local actual_path
    actual_path=$(yq eval '.spec.source.path // ""' "$file")

    # If single-source path exists, validate it
    if [ -n "$actual_path" ]; then
        actual_path="${actual_path#./}"  # Remove leading ./

        if [ "$actual_path" != "$expected_path" ]; then
            echo -e "${RED}✗ FAIL: $file${NC}"
            echo -e "  Expected: path: $expected_path"
            echo -e "  Found:    path: $actual_path"
            echo ""
            ((ERRORS++))
        else
            echo -e "${GREEN}✓ PASS: $file${NC}"
        fi
        return
    fi

    # Check for multi-source with $values reference
    local values_path
    values_path=$(yq eval '.spec.sources[].helm.valueFiles[]' "$file" 2>/dev/null | grep -E '^\$values/' | head -1 || true)

    if [ -n "$values_path" ]; then
        # Extract path from $values/path/to/dir/values.yaml
        local extracted_path
        extracted_path=$(echo "$values_path" | sed -E 's/^\$values\///' | sed -E 's/\/values\.yaml$//')
        extracted_path="${extracted_path#./}"

        if [ "$extracted_path" != "$expected_path" ]; then
            echo -e "${RED}✗ FAIL: $file${NC}"
            echo -e "  Expected: \$values/$expected_path/values.yaml"
            echo -e "  Found:    $values_path"
            echo ""
            ((ERRORS++))
        else
            echo -e "${GREEN}✓ PASS: $file${NC}"
        fi
        return
    fi

    # No path found - might be a pure Helm chart
    if yq eval '.spec.sources[].chart // .spec.source.chart // ""' "$file" | grep -q '.'; then
        echo -e "${YELLOW}⚠ SKIP: $file (Helm chart without path)${NC}"
        return
    fi

    echo -e "${RED}✗ FAIL: $file${NC}"
    echo -e "  No path found in spec.source.path or \$values reference"
    echo ""
    ((ERRORS++))
}

# Find and validate all ArgoCD Application files
echo "Checking ArgoCD Application manifests..."
echo "-----------------------------------------------------------------"
files=$(find . \( -name "app-of-apps.yaml" -o -name "application.yaml" \) -type f 2>/dev/null || true)

if [ -z "$files" ]; then
    echo -e "${YELLOW}No ArgoCD Application files found${NC}"
else
    while IFS= read -r file; do
        validate_argocd_app "$file"
    done <<< "$files"
fi
echo ""

# Summary
echo "================================================================="
echo "Summary"
echo "================================================================="
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All paths are valid!${NC}"
    exit 0
else
    echo -e "${RED}✗ $ERRORS validation error(s) found${NC}"
    echo ""
    echo "To fix these issues, run:"
    echo "  ./fix-argocd-paths.sh <bundle-directory>"
    exit 1
fi
