#!/usr/bin/env python3
"""
PaCMAP dimensionality reduction for k-mer frequency vectors

PaCMAP (Pairwise Controlled Manifold Approximation Projection) is a modern alternative
to UMAP that provides:
- 2-3x faster computation
- Better preservation of local and global structure
- More stable results across runs
- Better scalability to large datasets

Supports both dense (TSV) and sparse (NPZ) input formats for memory efficiency.
"""

import argparse
import sys
import os
import numpy as np
import pandas as pd
import pacmap
import matplotlib.pyplot as plt
import seaborn as sns
from scipy.sparse import load_npz, issparse

def parse_args():
    parser = argparse.ArgumentParser(
        description='Perform PaCMAP dimensionality reduction on k-mer frequency data'
    )

    parser.add_argument(
        '-i', '--input',
        required=True,
        help='Input k-mer frequency table (TSV format or NPZ sparse matrix)'
    )
    parser.add_argument(
        '-o', '--output',
        required=True,
        help='Output PaCMAP coordinates (TSV format)'
    )
    parser.add_argument(
        '-p', '--plot',
        default='pacmap_projection.png',
        help='Output plot file (PNG format)'
    )
    parser.add_argument(
        '-n', '--n-components',
        type=int,
        default=3,
        help='Number of PaCMAP dimensions [3]'
    )
    parser.add_argument(
        '--n-neighbors',
        type=int,
        default=15,
        help='Number of neighbors for PaCMAP [15]'
    )
    parser.add_argument(
        '--mn-ratio',
        type=float,
        default=0.5,
        help='Mid-near pairs ratio [0.5]'
    )
    parser.add_argument(
        '--fp-ratio',
        type=float,
        default=2.0,
        help='Further pairs ratio [2.0]'
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
    """
    Load k-mer frequency data from sparse matrix NPZ format.

    Args:
        npz_file: Path to .npz file (without extension, will load both matrix and metadata)

    Returns:
        metadata: DataFrame with read IDs and lengths
        features: Sparse matrix or dense array of k-mer frequencies
        feature_cols: List of k-mer names
    """
    # Load sparse matrix
    base_name = npz_file.replace('.npz', '')
    sparse_matrix = load_npz(f"{base_name}.npz")

    # Load metadata
    metadata_file = f"{base_name}_metadata.npz"
    if os.path.exists(metadata_file):
        meta_data = np.load(metadata_file, allow_pickle=True)
        read_ids = meta_data['read_ids']
        lengths = meta_data['lengths']
        kmer_names = meta_data['kmer_names']

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
        kmer_names = [f'kmer_{i}' for i in range(sparse_matrix.shape[1])]

    print(f"Loaded sparse matrix: {sparse_matrix.shape}", file=sys.stderr)
    print(f"Matrix format: {type(sparse_matrix).__name__}", file=sys.stderr)
    print(f"Sparsity: {100 * (1 - sparse_matrix.nnz / (sparse_matrix.shape[0] * sparse_matrix.shape[1])):.2f}%", file=sys.stderr)

    # PaCMAP requires dense arrays, so convert (memory spike but necessary)
    print(f"Converting to dense array for PaCMAP processing...", file=sys.stderr)
    dense_matrix = sparse_matrix.toarray()

    return metadata, dense_matrix, list(kmer_names)

def load_kmer_data(filename):
    """
    Load k-mer frequency data from TSV or NPZ format.

    Auto-detects format based on file extension.
    """
    # Check if input is sparse matrix format
    if filename.endswith('.npz'):
        return load_sparse_kmer_data(filename)

    # Load TSV format (original behavior)
    df = pd.read_csv(filename, delimiter="\t")

    # Separate metadata from features
    meta_cols = ["read", "length"]
    feature_cols = [x for x in df.columns if x not in meta_cols]

    metadata = df[meta_cols]
    features = df[feature_cols]

    print(f"Loaded dense matrix: {features.shape}", file=sys.stderr)

    return metadata, features, feature_cols

def perform_pacmap(features, n_components, n_neighbors, mn_ratio, fp_ratio, random_state, verbose):
    """
    Perform PaCMAP dimensionality reduction.

    PaCMAP parameters:
    - n_neighbors: Number of nearest neighbors (similar to UMAP)
    - MN_ratio: Controls mid-near pair generation (0.5 = balanced)
    - FP_ratio: Controls further pair generation (2.0 = more global structure)

    Args:
        features: Dense feature matrix
        n_components: Number of dimensions to reduce to
        n_neighbors: Number of neighbors for local structure
        mn_ratio: Mid-near pairs ratio
        fp_ratio: Further pairs ratio
        random_state: Random seed
        verbose: Verbosity level

    Returns:
        embedding: PaCMAP-transformed data
        reducer: Fitted PaCMAP object
    """
    print(f"\nPerforming PaCMAP dimensionality reduction...", file=sys.stderr)

    reducer = pacmap.PaCMAP(
        n_components=n_components,
        n_neighbors=n_neighbors,
        MN_ratio=mn_ratio,
        FP_ratio=fp_ratio,
        random_state=random_state,
        verbose=verbose
    )

    # Convert DataFrame to numpy if needed
    if isinstance(features, pd.DataFrame):
        features = features.values

    # Fit and transform
    embedding = reducer.fit_transform(features)

    print(f"PaCMAP completed successfully!", file=sys.stderr)

    return embedding, reducer

def create_output_dataframe(metadata, embedding, n_components):
    """Create output dataframe with PaCMAP coordinates."""
    # Create column names for PaCMAP dimensions
    # Use same naming as UMAP for drop-in compatibility
    pacmap_cols = [f"UMAP{i+1}" for i in range(n_components)]

    # Create DataFrame with PaCMAP coordinates
    df_pacmap = pd.DataFrame(embedding, columns=pacmap_cols)

    # Concatenate with metadata
    output = pd.concat([metadata.reset_index(drop=True), df_pacmap], axis=1)

    return output

def plot_pacmap(embedding, output_file, n_components):
    """Create visualization of PaCMAP projection."""
    if n_components >= 2:
        plt.figure(figsize=(12, 10))

        # Use seaborn for better aesthetics
        sns.set_style("whitegrid")

        # Plot first two dimensions
        plt.scatter(
            embedding[:, 0],
            embedding[:, 1],
            s=2,
            alpha=0.7,
            c=range(len(embedding)),
            cmap='viridis'
        )

        plt.xlabel("PaCMAP1", fontsize=14)
        plt.ylabel("PaCMAP2", fontsize=14)
        plt.title(f"PaCMAP Projection of {len(embedding)} reads", fontsize=16)
        plt.colorbar(label='Read index')

        plt.tight_layout()
        plt.savefig(output_file, dpi=300, bbox_inches='tight')
        plt.close()

        print(f"Plot saved to {output_file}", file=sys.stderr)
    else:
        print(f"Skipping plot (n_components={n_components} < 2)", file=sys.stderr)

def main():
    args = parse_args()

    # Load data
    print(f"Loading k-mer frequency data from {args.input}...", file=sys.stderr)
    metadata, features, feature_names = load_kmer_data(args.input)
    print(f"Loaded {len(metadata)} reads with {len(feature_names)} features", file=sys.stderr)

    # Perform PaCMAP
    print(f"\nPaCMAP Configuration:", file=sys.stderr)
    print(f"  n_components={args.n_components}", file=sys.stderr)
    print(f"  n_neighbors={args.n_neighbors}", file=sys.stderr)
    print(f"  MN_ratio={args.mn_ratio}", file=sys.stderr)
    print(f"  FP_ratio={args.fp_ratio}", file=sys.stderr)
    print(f"  random_state={args.random_state}", file=sys.stderr)

    embedding, reducer = perform_pacmap(
        features,
        args.n_components,
        args.n_neighbors,
        args.mn_ratio,
        args.fp_ratio,
        args.random_state,
        args.verbose
    )

    # Create output DataFrame
    output_df = create_output_dataframe(metadata, embedding, args.n_components)

    # Save results
    print(f"\nSaving PaCMAP coordinates to {args.output}...", file=sys.stderr)
    output_df.to_csv(args.output, sep="\t", index=False)

    # Create plot
    if args.plot:
        print(f"Creating visualization...", file=sys.stderr)
        plot_pacmap(embedding, args.plot, args.n_components)

    print("\nPaCMAP dimensionality reduction complete!", file=sys.stderr)

    # Print summary statistics
    print("\nSummary:", file=sys.stderr)
    print(f"  Input reads: {len(metadata)}", file=sys.stderr)
    print(f"  Input features: {len(feature_names)}", file=sys.stderr)
    print(f"  Output dimensions: {args.n_components}", file=sys.stderr)
    print(f"  Algorithm: PaCMAP (faster alternative to UMAP)", file=sys.stderr)

if __name__ == "__main__":
    main()
