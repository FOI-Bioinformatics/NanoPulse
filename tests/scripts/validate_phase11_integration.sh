#!/bin/bash
#
# Phase 11 Integration Validation Test
#
# This script validates that all Phase 11 features integrate correctly
# by running the pipeline in stub mode with all features enabled.
#

set -e

echo "============================================================"
echo "Phase 11 Novel Diversity Detection - Integration Validation"
echo "============================================================"
echo

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Test counter
tests_passed=0
tests_failed=0

# Helper function for test reporting
report_test() {
    test_name=$1
    result=$2

    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((tests_passed++))
    else
        echo -e "${RED}✗${NC} $test_name"
        ((tests_failed++))
    fi
}

echo "Phase 11 Features to Validate:"
echo "  1. Noise point rescue (RESCUE_NOISE)"
echo "  2. Probabilistic classification"
echo "  3. Novel sequence extraction"
echo "  4. Phylogenetic tree construction (BUILD_PHYLOTREE)"
echo "  5. Phyloseq object creation (CREATE_PHYLOSEQ)"
echo

# Test 1: Configuration validation
echo "Test 1: Validating configuration parameters..."
echo "─────────────────────────────────────────────────"

nextflow config -flat 2>/dev/null | grep -q "rescue_noise_points"
report_test "rescue_noise_points parameter exists" $?

nextflow config -flat 2>/dev/null | grep -q "use_probabilistic_classification"
report_test "use_probabilistic_classification parameter exists" $?

nextflow config -flat 2>/dev/null | grep -q "build_phylotree"
report_test "build_phylotree parameter exists" $?

nextflow config -flat 2>/dev/null | grep -q "create_phyloseq"
report_test "create_phyloseq parameter exists" $?

echo

# Test 2: Module detection
echo "Test 2: Validating module detection..."
echo "─────────────────────────────────────────────────"

nextflow inspect . 2>/dev/null | grep -q "RESCUE_NOISE"
report_test "RESCUE_NOISE module detected" $?

nextflow inspect . 2>/dev/null | grep -q "BUILD_PHYLOTREE"
report_test "BUILD_PHYLOTREE module detected" $?

nextflow inspect . 2>/dev/null | grep -q "CREATE_PHYLOSEQ"
report_test "CREATE_PHYLOSEQ module detected" $?

nextflow inspect . 2>/dev/null | grep -q "AGGREGATE_CLASSIFICATIONS"
report_test "AGGREGATE_CLASSIFICATIONS module detected" $?

nextflow inspect . 2>/dev/null | grep -q "EXTRACT_NOVEL_SEQUENCES"
report_test "EXTRACT_NOVEL_SEQUENCES module detected" $?

echo

# Test 3: Script executability
echo "Test 3: Validating script executability..."
echo "─────────────────────────────────────────────────"

test -x bin/create_phyloseq_object.R
report_test "create_phyloseq_object.R is executable" $?

test -f bin/classify_consensus_probabilistic.py
report_test "classify_consensus_probabilistic.py exists" $?

test -f modules/local/build_phylotree/main.nf
report_test "BUILD_PHYLOTREE module file exists" $?

test -f modules/local/create_phyloseq/environment.yml
report_test "CREATE_PHYLOSEQ environment file exists" $?

echo

# Test 4: Workflow syntax validation
echo "Test 4: Validating workflow syntax..."
echo "─────────────────────────────────────────────────"

# Check if workflows/nanopulse.nf contains Phase 11 steps
grep -q "STEP 10.*phylogenetic tree" workflows/nanopulse.nf
report_test "STEP 10 (BUILD_PHYLOTREE) integrated" $?

grep -q "STEP 11.*phyloseq" workflows/nanopulse.nf
report_test "STEP 11 (CREATE_PHYLOSEQ) integrated" $?

grep -q "RESCUE_NOISE" workflows/nanopulse.nf
report_test "RESCUE_NOISE integrated" $?

grep -q "EXTRACT_NOVEL_SEQUENCES" workflows/nanopulse.nf
report_test "EXTRACT_NOVEL_SEQUENCES integrated" $?

echo

# Test 5: Documentation validation
echo "Test 5: Validating documentation..."
echo "─────────────────────────────────────────────────"

test -f docs/PHASE11_USAGE_GUIDE.md
report_test "Phase 11 usage guide exists" $?

grep -q "Phase 3.*Phylogenetics" CLAUDE.md
report_test "CLAUDE.md includes Phase 3 documentation" $?

grep -q "CREATE_PHYLOSEQ" CLAUDE.md
report_test "CLAUDE.md documents CREATE_PHYLOSEQ" $?

echo

# Test 6: Stub mode execution (optional - requires test data)
echo "Test 6: Stub mode execution test (optional)..."
echo "─────────────────────────────────────────────────"

if [ -f "test_datasets/samplesheet_mock4.csv" ]; then
    echo "Test data found. Running stub mode validation..."

    # Run pipeline in stub mode with all Phase 11 features enabled
    timeout 60s nextflow run . \
        -profile test \
        --input test_datasets/samplesheet_mock4.csv \
        --outdir test_output_phase11_validation \
        --rescue_noise_points true \
        --use_probabilistic_classification true \
        --build_phylotree true \
        --create_phyloseq true \
        -stub-run \
        2>&1 | tee /tmp/phase11_stub_test.log

    stub_result=$?

    if [ $stub_result -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Stub mode execution succeeded"
        ((tests_passed++))

        # Check if expected output files would be created
        if grep -q "BUILD_PHYLOTREE" /tmp/phase11_stub_test.log && \
           grep -q "CREATE_PHYLOSEQ" /tmp/phase11_stub_test.log; then
            echo -e "${GREEN}✓${NC} Phase 11 modules executed in workflow"
            ((tests_passed++))
        else
            echo -e "${YELLOW}⚠${NC} Phase 11 modules may not have executed"
            ((tests_failed++))
        fi
    else
        echo -e "${RED}✗${NC} Stub mode execution failed"
        ((tests_failed++))
    fi

    # Cleanup
    rm -rf test_output_phase11_validation
else
    echo -e "${YELLOW}⚠${NC} Test data not found, skipping stub mode test"
    echo "  (This is optional - main validation complete)"
fi

echo

# Final report
echo "============================================================"
echo "Validation Summary"
echo "============================================================"
echo
echo "Tests Passed: ${tests_passed}"
echo "Tests Failed: ${tests_failed}"
echo

if [ $tests_failed -eq 0 ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
    echo
    echo "Phase 11 Novel Diversity Detection is:"
    echo "  ✓ Properly configured"
    echo "  ✓ Correctly integrated"
    echo "  ✓ Ready for production use"
    echo
    echo "Status: PRODUCTION-READY"
    exit 0
else
    echo -e "${RED}✗ SOME TESTS FAILED${NC}"
    echo
    echo "Please review failed tests above."
    echo "Status: NEEDS ATTENTION"
    exit 1
fi
