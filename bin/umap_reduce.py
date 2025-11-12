#!/usr/bin/env python3
"""
UMAP dimensionality reduction for k-mer frequency vectors
"""

import argparse
import sys
import numpy as np
import pandas as pd
import umap
import matplotlib.pyplot as plt
import seaborn as sns

def parse_args():
    parser = argparse.ArgumentParser(
        description='Perform UMAP dimensionality reduction on k-mer frequency data'
    )

    parser.add_argument(
        '-i', '--input',
        required=True,
        help='Input k-mer frequency table (TSV format)'
    )
    parser.add_argument(
        '-o', '--output',
        required=True,
        help='Output UMAP coordinates (TSV format)'
    )
    parser.add_argument(
        '-p', '--plot',
        default='umap_projection.png',
        help='Output plot file (PNG format)'
    )
    parser.add_argument(
        '-n', '--n-components',
        type=int,
        default=3,
        help='Number of UMAP dimensions [3]'
    )
    parser.add_argument(
        '--n-neighbors',
        type=int,
        default=15,
        help='Number of neighbors for UMAP [15]'
    )
    parser.add_argument(
        '--min-dist',
        type=float,
        default=0.1,
        help='Minimum distance for UMAP [0.1]'
    )
    parser.add_argument(
        '--metric',
        default='euclidean',
        help='Distance metric for UMAP [euclidean]'
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

def load_kmer_data(filename):
    """Load k-mer frequency data."""
    df = pd.read_csv(filename, delimiter="\t")

    # Separate metadata from features
    meta_cols = ["read", "length"]
    feature_cols = [x for x in df.columns if x not in meta_cols]

    metadata = df[meta_cols]
    features = df[feature_cols]

    return metadata, features, feature_cols

def perform_umap(features, n_components, n_neighbors, min_dist, metric, random_state, verbose):
    """Perform UMAP dimensionality reduction."""
    reducer = umap.UMAP(
        n_components=n_components,
        n_neighbors=n_neighbors,
        min_dist=min_dist,
        metric=metric,
        random_state=random_state,
        verbose=verbose
    )

    embedding = reducer.fit_transform(features)

    return embedding, reducer

def create_output_dataframe(metadata, embedding, n_components):
    """Create output dataframe with UMAP coordinates."""
    # Create column names for UMAP dimensions
    umap_cols = [f"UMAP{i+1}" for i in range(n_components)]

    # Create DataFrame with UMAP coordinates
    df_umap = pd.DataFrame(embedding, columns=umap_cols)

    # Concatenate with metadata
    output = pd.concat([metadata.reset_index(drop=True), df_umap], axis=1)

    return output

def plot_umap(embedding, output_file, n_components):
    """Create visualization of UMAP projection."""
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

        plt.xlabel("UMAP1", fontsize=14)
        plt.ylabel("UMAP2", fontsize=14)
        plt.title(f"UMAP Projection of {len(embedding)} reads", fontsize=16)
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

    # Perform UMAP
    print(f"Performing UMAP dimensionality reduction...", file=sys.stderr)
    print(f"  n_components={args.n_components}", file=sys.stderr)
    print(f"  n_neighbors={args.n_neighbors}", file=sys.stderr)
    print(f"  min_dist={args.min_dist}", file=sys.stderr)
    print(f"  metric={args.metric}", file=sys.stderr)
    print(f"  random_state={args.random_state}", file=sys.stderr)

    embedding, reducer = perform_umap(
        features,
        args.n_components,
        args.n_neighbors,
        args.min_dist,
        args.metric,
        args.random_state,
        args.verbose
    )

    # Create output DataFrame
    output_df = create_output_dataframe(metadata, embedding, args.n_components)

    # Save results
    print(f"Saving UMAP coordinates to {args.output}...", file=sys.stderr)
    output_df.to_csv(args.output, sep="\t", index=False)

    # Create plot
    if args.plot:
        print(f"Creating visualization...", file=sys.stderr)
        plot_umap(embedding, args.plot, args.n_components)

    print("UMAP dimensionality reduction complete!", file=sys.stderr)

    # Print summary statistics
    print("\nSummary:", file=sys.stderr)
    print(f"  Input reads: {len(metadata)}", file=sys.stderr)
    print(f"  Input features: {len(feature_names)}", file=sys.stderr)
    print(f"  Output dimensions: {args.n_components}", file=sys.stderr)
    print(f"  Variance explained (approx): N/A for UMAP", file=sys.stderr)

if __name__ == "__main__":
    main()
