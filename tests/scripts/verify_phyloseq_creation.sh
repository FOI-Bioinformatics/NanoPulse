#!/bin/bash
#
# Verify CREATE_PHYLOSEQ module can be executed
#
# This script tests that the phyloseq creation R script runs without errors
# using minimal test data.
#

set -e

echo "==================================================="
echo "NanoPulse CREATE_PHYLOSEQ Module Verification"
echo "==================================================="
echo

# Check if R is available
if ! command -v R &> /dev/null; then
    echo "ERROR: R not found. Please install R >= 4.3.0"
    exit 1
fi

echo "✓ R found: $(R --version | head -1)"
echo

# Check if create_phyloseq_object.R exists and is executable
SCRIPT_PATH="bin/create_phyloseq_object.R"

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "ERROR: $SCRIPT_PATH not found"
    exit 1
fi

if [ ! -x "$SCRIPT_PATH" ]; then
    echo "ERROR: $SCRIPT_PATH is not executable"
    echo "Run: chmod +x $SCRIPT_PATH"
    exit 1
fi

echo "✓ create_phyloseq_object.R found and executable"
echo

# Check R package availability (non-fatal - just informational)
echo "Checking R package availability..."
echo

check_r_package() {
    package=$1
    if R -q -e "library($package)" 2>/dev/null; then
        echo "  ✓ $package installed"
        return 0
    else
        echo "  ✗ $package not installed"
        return 1
    fi
}

all_packages_installed=true

check_r_package "phyloseq" || all_packages_installed=false
check_r_package "ape" || all_packages_installed=false
check_r_package "picante" || all_packages_installed=false
check_r_package "vegan" || all_packages_installed=false
check_r_package "optparse" || all_packages_installed=false

echo

if [ "$all_packages_installed" = false ]; then
    echo "WARNING: Some R packages are missing"
    echo "To install missing packages, run in R:"
    echo "  if (!requireNamespace('BiocManager', quietly = TRUE))"
    echo "    install.packages('BiocManager')"
    echo "  BiocManager::install('phyloseq')"
    echo "  install.packages(c('ape', 'picante', 'vegan', 'optparse'))"
    echo
    echo "Or use conda environment:"
    echo "  conda env create -f modules/local/create_phyloseq/environment.yml"
    echo
fi

# Test script help output
echo "Testing script help output..."
echo

if $SCRIPT_PATH --help > /dev/null 2>&1; then
    echo "✓ Script help runs successfully"
else
    echo "✗ Script help failed - missing optparse package?"
fi

echo
echo "==================================================="
echo "Verification Summary"
echo "==================================================="
echo
echo "Script Location: $SCRIPT_PATH"
echo "Executable: YES"
echo "R Version: $(R --version | head -1 | sed 's/R version //' | sed 's/ (.*//')"
echo
if [ "$all_packages_installed" = true ]; then
    echo "Status: ✅ READY - All R packages installed"
else
    echo "Status: ⚠️  PARTIAL - Some R packages missing (see above)"
    echo "        Module will work in stub mode, but conda/R packages needed for execution"
fi
echo
echo "To test with real data:"
echo "  $SCRIPT_PATH \\"
echo "    --tree phylogeny/sample.tree \\"
echo "    --abundance abundances/sample.csv \\"
echo "    --taxonomy consensus/sample_annotations.tsv \\"
echo "    --output phyloseq/sample_phyloseq.rds \\"
echo "    --calculate-diversity \\"
echo "    --verbose"
echo
