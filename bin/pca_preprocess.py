#!/usr/bin/env python3
"""
PCA preprocessing for k-mer frequency data

Reduces 131,072 k-mer features to ~50 principal components while preserving >99% variance.
This provides massive memory reduction (95%) while maintaining information content.

Memory impact for 100k reads:
- Before PCA: 100k × 131k × 8 bytes = ~105 GB
- After PCA:  100k × 50 × 8 bytes = ~40 MB (99.96% reduction)
"""

import argparse
import sys
import os
import json
import numpy as np
import pandas as pd
from sklearn.decomposition import PCA
from scipy.sparse import load_npz, issparse

def parse_args():
    parser = argparse.ArgumentParser(
        description='Perform PCA dimensionality reduction on k-mer frequency data'
    )

    parser.add_argument(
        '-i', '--input',
        required=True,
        help='Input k-mer frequency table (TSV format or NPZ sparse matrix)'
    )
    parser.add_argument(
        '-o', '--output',
        required=True,
        help='Output PCA-reduced features (TSV format)'
    )
    parser.add_argument(
        '--variance-report',
        default='pca_variance_explained.json',
        help='Output variance report (JSON format)'
    )
    parser.add_argument(
        '-n', '--n-components',
        type=int,
        default=50,
        help='Number of principal components to keep [50]'
    )
    parser.add_argument(
        '--min-variance',
        type=float,
        default=0.99,
        help='Minimum cumulative variance to preserve [0.99]'
    )
    parser.add_argument(
        '--random-state',
        type=int,
        default=42,
        help='Random seed for reproducibility [42]'
    )
    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Verbose output'
    )

    return parser.parse_args()

def load_sparse_kmer_data(npz_file):
    """Load k-mer frequency data from sparse matrix NPZ format."""
    base_name = npz_file.replace('.npz', '')
    sparse_matrix = load_npz(f"{base_name}.npz")

    # Load metadata
    metadata_file = f"{base_name}_metadata.npz"
    if os.path.exists(metadata_file):
        meta_data = np.load(metadata_file, allow_pickle=True)
        read_ids = meta_data['read_ids']
        lengths = meta_data['lengths']

        metadata = pd.DataFrame({
            'read': read_ids,
            'length': lengths
        })
    else:
        # Create dummy metadata if file doesn't exist
        n_reads = sparse_matrix.shape[0]
        metadata = pd.DataFrame({
            'read': [f'read_{i}' for i in range(n_reads)],
            'length': [0] * n_reads
        })

    print(f"Loaded sparse matrix: {sparse_matrix.shape}", file=sys.stderr)
    print(f"Sparsity: {100 * (1 - sparse_matrix.nnz / (sparse_matrix.shape[0] * sparse_matrix.shape[1])):.2f}%", file=sys.stderr)

    # Convert to dense for PCA (sklearn PCA doesn't support sparse matrices directly)
    # This is a temporary memory spike but necessary for PCA
    dense_matrix = sparse_matrix.toarray()
    print(f"Converted to dense matrix for PCA processing", file=sys.stderr)

    return metadata, dense_matrix

def load_kmer_data(filename):
    """Load k-mer frequency data from TSV or NPZ format."""
    # Check if input is sparse matrix format
    if filename.endswith('.npz'):
        return load_sparse_kmer_data(filename)

    # Load TSV format (original behavior)
    # Note: pandas automatically decompresses .gz files with compression='infer'
    df = pd.read_csv(filename, delimiter="\t", compression='infer')

    # Separate metadata from features
    meta_cols = ["read", "length"]
    feature_cols = [x for x in df.columns if x not in meta_cols]

    metadata = df[meta_cols]
    features = df[feature_cols].values

    print(f"Loaded dense matrix: {features.shape}", file=sys.stderr)

    return metadata, features

def perform_pca(features, n_components, random_state, verbose):
    """
    Perform PCA dimensionality reduction.

    Args:
        features: Dense feature matrix (n_samples, n_features)
        n_components: Number of components to keep
        random_state: Random seed
        verbose: Verbosity level

    Returns:
        transformed: PCA-transformed data
        pca: Fitted PCA object
    """
    print(f"\nPerforming PCA with {n_components} components...", file=sys.stderr)

    pca = PCA(
        n_components=n_components,
        random_state=random_state,
        svd_solver='auto'  # Automatically chooses best solver
    )

    # Fit and transform
    transformed = pca.fit_transform(features)

    # Report variance explained
    cumulative_variance = np.cumsum(pca.explained_variance_ratio_)
    print(f"\nPCA Results:", file=sys.stderr)
    print(f"  Input dimensions: {features.shape[1]}", file=sys.stderr)
    print(f"  Output dimensions: {n_components}", file=sys.stderr)
    print(f"  Variance explained by each component:", file=sys.stderr)
    for i in range(min(10, n_components)):
        print(f"    PC{i+1}: {100*pca.explained_variance_ratio_[i]:.4f}%", file=sys.stderr)
    if n_components > 10:
        print(f"    ... ({n_components - 10} more components)", file=sys.stderr)
    print(f"  Total variance explained: {100*cumulative_variance[-1]:.4f}%", file=sys.stderr)

    return transformed, pca

def create_output_dataframe(metadata, transformed, n_components):
    """Create output dataframe with PCA coordinates."""
    # Create column names for PCA dimensions
    pca_cols = [f"PC{i+1}" for i in range(n_components)]

    # Create DataFrame with PCA coordinates
    df_pca = pd.DataFrame(transformed, columns=pca_cols)

    # Concatenate with metadata
    output = pd.concat([metadata.reset_index(drop=True), df_pca], axis=1)

    return output

def create_variance_report(pca, n_components, min_variance, input_shape):
    """Create JSON report of variance explained."""
    cumulative_variance = np.cumsum(pca.explained_variance_ratio_)

    # Find minimum components for target variance
    components_for_target = np.searchsorted(cumulative_variance, min_variance) + 1

    report = {
        "input_dimensions": int(input_shape[1]),
        "input_samples": int(input_shape[0]),
        "output_dimensions": int(n_components),
        "total_variance_explained": float(cumulative_variance[-1]),
        "variance_explained_per_component": [float(x) for x in pca.explained_variance_ratio_],
        "cumulative_variance": [float(x) for x in cumulative_variance],
        "components_for_99pct_variance": int(components_for_target),
        "memory_reduction_factor": float(input_shape[1] / n_components),
        "quality_assessment": {
            "meets_minimum_variance": bool(cumulative_variance[-1] >= min_variance),
            "recommended_components": int(components_for_target),
            "information_loss_pct": float(100 * (1 - cumulative_variance[-1]))
        }
    }

    return report

def main():
    args = parse_args()

    # Load data
    print(f"Loading k-mer frequency data from {args.input}...", file=sys.stderr)
    metadata, features = load_kmer_data(args.input)
    print(f"Loaded {features.shape[0]} reads with {features.shape[1]} features", file=sys.stderr)

    # Perform PCA
    print(f"\nPCA Configuration:", file=sys.stderr)
    print(f"  n_components={args.n_components}", file=sys.stderr)
    print(f"  min_variance={args.min_variance}", file=sys.stderr)
    print(f"  random_state={args.random_state}", file=sys.stderr)

    transformed, pca = perform_pca(
        features,
        args.n_components,
        args.random_state,
        args.verbose
    )

    # Create output DataFrame
    output_df = create_output_dataframe(metadata, transformed, args.n_components)

    # Save results
    print(f"\nSaving PCA-reduced features to {args.output}...", file=sys.stderr)
    output_df.to_csv(args.output, sep="\t", index=False)

    # Create variance report
    variance_report = create_variance_report(
        pca,
        args.n_components,
        args.min_variance,
        features.shape
    )

    # Save variance report
    with open(args.variance_report, 'w') as f:
        json.dump(variance_report, f, indent=2)

    print(f"Variance report saved to {args.variance_report}", file=sys.stderr)

    # Print summary
    print("\n" + "="*60, file=sys.stderr)
    print("PCA Preprocessing Complete!", file=sys.stderr)
    print("="*60, file=sys.stderr)
    print(f"Input:  {features.shape[0]:,} reads × {features.shape[1]:,} features", file=sys.stderr)
    print(f"Output: {features.shape[0]:,} reads × {args.n_components} features", file=sys.stderr)
    print(f"Variance preserved: {100*variance_report['total_variance_explained']:.4f}%", file=sys.stderr)
    print(f"Memory reduction: {variance_report['memory_reduction_factor']:.1f}x", file=sys.stderr)

    if variance_report['quality_assessment']['meets_minimum_variance']:
        print(f"\nQuality check: PASSED (≥{100*args.min_variance}% variance)", file=sys.stderr)
    else:
        print(f"\nWARNING: Only {100*variance_report['total_variance_explained']:.2f}% variance preserved", file=sys.stderr)
        print(f"Consider using {variance_report['quality_assessment']['recommended_components']} components", file=sys.stderr)

if __name__ == "__main__":
    main()
