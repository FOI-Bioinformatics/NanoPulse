#!/usr/bin/env python3
"""
Generate synthetic NPZ test data for PCA module testing.

Creates sparse k-mer frequency matrices compatible with KMERFREQ output format.
Generates two NPZ files:
  1. kmer_freqs.npz - scipy CSR sparse matrix (n_reads × n_features)
  2. kmer_freqs_metadata.npz - read IDs and sequence lengths
"""

import numpy as np
from scipy.sparse import csr_matrix, save_npz
import argparse
from pathlib import Path


def generate_synthetic_kmer_data(
    n_reads=100,
    kmer_size=9,
    sparsity=0.99,
    seed=42
):
    """
    Generate synthetic k-mer frequency data.

    Args:
        n_reads: Number of synthetic reads
        kmer_size: K-mer size (9 = 4^9 = 262,144 possible k-mers)
        sparsity: Fraction of zero entries (0.99 = 99% sparse)
        seed: Random seed for reproducibility

    Returns:
        sparse_matrix: scipy CSR sparse matrix
        read_ids: List of read identifiers
        read_lengths: Array of read lengths
    """
    np.random.seed(seed)

    # Calculate number of k-mer features
    n_features = 4 ** kmer_size

    print(f"Generating synthetic k-mer data:")
    print(f"  - {n_reads} reads")
    print(f"  - {n_features:,} k-mer features ({kmer_size}-mers)")
    print(f"  - {sparsity*100:.1f}% sparsity")

    # Generate sparse matrix
    # Each read has ~(1-sparsity) of features with non-zero counts
    n_nonzero_per_read = int(n_features * (1 - sparsity))

    data = []
    row_indices = []
    col_indices = []

    for read_idx in range(n_reads):
        # Randomly select which k-mers are present in this read
        kmer_indices = np.random.choice(n_features, size=n_nonzero_per_read, replace=False)

        # Generate k-mer counts (1-100)
        counts = np.random.randint(1, 100, size=n_nonzero_per_read)

        # Add to sparse matrix data structures
        data.extend(counts)
        row_indices.extend([read_idx] * n_nonzero_per_read)
        col_indices.extend(kmer_indices)

    # Create CSR sparse matrix (same format as KMERFREQ output)
    sparse_matrix = csr_matrix(
        (data, (row_indices, col_indices)),
        shape=(n_reads, n_features),
        dtype=np.int32
    )

    # Calculate actual sparsity
    actual_sparsity = 1 - (sparse_matrix.nnz / (n_reads * n_features))
    print(f"  - Actual sparsity: {actual_sparsity*100:.2f}%")
    print(f"  - Non-zero entries: {sparse_matrix.nnz:,}")
    print(f"  - Matrix size: {n_reads} × {n_features:,}")

    # Generate metadata
    read_ids = [f"synthetic_read_{i:04d}" for i in range(n_reads)]
    read_lengths = np.random.randint(1000, 2000, size=n_reads)  # Read lengths 1-2kb

    return sparse_matrix, read_ids, read_lengths


def save_kmer_npz_files(sparse_matrix, read_ids, read_lengths, output_dir):
    """
    Save k-mer data in KMERFREQ NPZ output format.

    Args:
        sparse_matrix: scipy CSR sparse matrix
        read_ids: List of read identifiers
        read_lengths: Array of read lengths
        output_dir: Output directory path
    """
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Save sparse matrix (kmer_freqs.npz)
    matrix_path = output_dir / "kmer_freqs.npz"
    save_npz(matrix_path, sparse_matrix)
    print(f"\nSaved sparse matrix: {matrix_path}")
    print(f"  File size: {matrix_path.stat().st_size / 1024:.1f} KB")

    # Save metadata (kmer_freqs_metadata.npz)
    metadata_path = output_dir / "kmer_freqs_metadata.npz"
    np.savez(
        metadata_path,
        read_ids=np.array(read_ids, dtype=object),
        lengths=read_lengths  # Note: key must be 'lengths' to match pca_preprocess.py expectation
    )
    print(f"Saved metadata: {metadata_path}")
    print(f"  File size: {metadata_path.stat().st_size / 1024:.1f} KB")

    # Verify saved data can be loaded
    print("\nVerifying saved data...")
    loaded_matrix = np.load(matrix_path, allow_pickle=True)
    loaded_metadata = np.load(metadata_path, allow_pickle=True)

    print(f"  Matrix keys: {list(loaded_matrix.keys())}")
    print(f"  Metadata keys: {list(loaded_metadata.keys())}")
    print(f"  Read IDs sample: {loaded_metadata['read_ids'][:3]}")
    print(f"  Read lengths sample: {loaded_metadata['lengths'][:3]}")  # Using 'lengths' key
    print("\n✓ Verification successful!")


def main():
    parser = argparse.ArgumentParser(
        description="Generate synthetic NPZ test data for PCA module"
    )
    parser.add_argument(
        '--n-reads',
        type=int,
        default=100,
        help='Number of synthetic reads (default: 100)'
    )
    parser.add_argument(
        '--kmer-size',
        type=int,
        default=9,
        help='K-mer size (default: 9, gives 262,144 features)'
    )
    parser.add_argument(
        '--sparsity',
        type=float,
        default=0.99,
        help='Sparsity level 0-1 (default: 0.99 = 99%% sparse)'
    )
    parser.add_argument(
        '--output-dir',
        type=str,
        default='tests/testdata/nanopore/analysis',
        help='Output directory (default: tests/testdata/nanopore/analysis)'
    )
    parser.add_argument(
        '--seed',
        type=int,
        default=42,
        help='Random seed for reproducibility (default: 42)'
    )

    args = parser.parse_args()

    # Generate synthetic data
    sparse_matrix, read_ids, read_lengths = generate_synthetic_kmer_data(
        n_reads=args.n_reads,
        kmer_size=args.kmer_size,
        sparsity=args.sparsity,
        seed=args.seed
    )

    # Save NPZ files
    save_kmer_npz_files(sparse_matrix, read_ids, read_lengths, args.output_dir)


if __name__ == '__main__':
    main()
