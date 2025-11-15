#!/usr/bin/env python3
"""
Memory estimation and validation for UMAP dimensionality reduction

This script estimates memory requirements based on input data dimensions
and validates that sufficient memory is available before running UMAP.

Memory estimation formula:
- Base memory = n_reads × n_features × 8 bytes (float64)
- UMAP overhead ≈ 4x base memory (graph construction, embedding)
- Total ≈ 5x base memory

Typical scenarios:
- 100k reads × 131k features: ~525 GB
- 50k reads × 131k features: ~260 GB
- 10k reads × 131k features: ~52 GB
- 1k reads × 131k features: ~5.2 GB
"""

import argparse
import sys
import gzip
import psutil

def parse_args():
    parser = argparse.ArgumentParser(
        description='Estimate memory requirements for UMAP'
    )
    parser.add_argument(
        '-i', '--input',
        required=True,
        help='Input k-mer frequency file (TSV, optionally gzipped)'
    )
    parser.add_argument(
        '--safety-factor',
        type=float,
        default=5.0,
        help='Memory safety factor (default: 5.0x base memory)'
    )
    parser.add_argument(
        '--fail-on-insufficient',
        action='store_true',
        help='Exit with error if insufficient memory available'
    )

    return parser.parse_args()

def count_lines_and_columns(filename):
    """Count lines and columns in TSV file (gzipped or not)."""

    # Determine if file is gzipped
    if filename.endswith('.gz'):
        open_func = gzip.open
        mode = 'rt'
    else:
        open_func = open
        mode = 'r'

    with open_func(filename, mode) as f:
        # Read header to get number of columns
        header = f.readline().strip()
        n_cols = len(header.split('\t'))

        # Count data lines (excluding header)
        n_lines = sum(1 for _ in f)

    return n_lines, n_cols

def get_available_memory():
    """Get available system memory in GB."""
    mem = psutil.virtual_memory()
    return mem.available / (1024**3)  # Convert bytes to GB

def estimate_memory_gb(n_reads, n_features, safety_factor=5.0):
    """
    Estimate memory requirement for UMAP.

    Parameters:
        n_reads: Number of reads/samples
        n_features: Number of features (k-mer frequencies)
        safety_factor: Multiplier for UMAP overhead (default: 5.0)

    Returns:
        Estimated memory in GB
    """
    # Base memory: n_reads × n_features × 8 bytes (float64)
    base_memory_bytes = n_reads * n_features * 8

    # UMAP overhead includes:
    # - K-NN graph construction
    # - Optimization iterations
    # - Embedding computation
    # Conservative estimate: 4x base memory overhead
    total_memory_bytes = base_memory_bytes * safety_factor

    # Convert to GB
    memory_gb = total_memory_bytes / (1024**3)

    return memory_gb

def format_memory(gb):
    """Format memory value with appropriate unit."""
    if gb < 1:
        return f"{gb * 1024:.1f} MB"
    else:
        return f"{gb:.1f} GB"

def main():
    args = parse_args()

    # Count input dimensions
    print("Analyzing input data dimensions...", file=sys.stderr)
    n_reads, n_cols = count_lines_and_columns(args.input)

    # K-mer frequency files have 2 metadata columns (read, length)
    # All other columns are k-mer features
    n_features = n_cols - 2

    print(f"  Reads: {n_reads:,}", file=sys.stderr)
    print(f"  Features: {n_features:,}", file=sys.stderr)
    print(f"  Data size: {n_reads:,} × {n_features:,} matrix", file=sys.stderr)

    # Estimate memory requirement
    estimated_memory = estimate_memory_gb(n_reads, n_features, args.safety_factor)

    print(f"\nMemory estimation:", file=sys.stderr)
    print(f"  Base memory: {format_memory(estimated_memory / args.safety_factor)}", file=sys.stderr)
    print(f"  Estimated total (with {args.safety_factor}x overhead): {format_memory(estimated_memory)}", file=sys.stderr)

    # Check available memory
    available_memory = get_available_memory()
    print(f"  Available memory: {format_memory(available_memory)}", file=sys.stderr)

    # Determine if sufficient memory is available
    if estimated_memory > available_memory:
        print(f"\nWARNING: Insufficient memory!", file=sys.stderr)
        print(f"  Required: {format_memory(estimated_memory)}", file=sys.stderr)
        print(f"  Available: {format_memory(available_memory)}", file=sys.stderr)
        print(f"  Deficit: {format_memory(estimated_memory - available_memory)}", file=sys.stderr)
        print(f"\nRecommendations:", file=sys.stderr)
        print(f"  1. Use --umap_set_size to reduce input reads", file=sys.stderr)
        print(f"  2. Run on a machine with more RAM", file=sys.stderr)
        print(f"  3. Use the 'lowmem' profile with subsampling", file=sys.stderr)

        if args.fail_on_insufficient:
            sys.exit(1)
    else:
        surplus = available_memory - estimated_memory
        print(f"\nMemory check: PASS ✓", file=sys.stderr)
        print(f"  Surplus memory: {format_memory(surplus)}", file=sys.stderr)

    # Output machine-readable result
    print(f"{estimated_memory:.2f}")  # GB to stdout for capture

if __name__ == "__main__":
    main()
