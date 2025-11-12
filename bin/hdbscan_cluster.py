#!/usr/bin/env python3
"""
HDBSCAN clustering of UMAP-reduced data
Handles edge cases and ensures reproducibility
"""

import argparse
import sys
import json
import numpy as np
import pandas as pd
import hdbscan
import matplotlib.pyplot as plt
import seaborn as sns
from collections import Counter

def parse_args():
    parser = argparse.ArgumentParser(
        description='Perform HDBSCAN clustering on UMAP coordinates'
    )

    parser.add_argument(
        '-i', '--input',
        required=True,
        help='Input UMAP coordinates (TSV format)'
    )
    parser.add_argument(
        '-o', '--output',
        required=True,
        help='Output cluster assignments (TSV format)'
    )
    parser.add_argument(
        '-p', '--plot',
        default='hdbscan_clusters.png',
        help='Output cluster plot (PNG format)'
    )
    parser.add_argument(
        '--cluster-info',
        default='cluster_info.json',
        help='Output cluster statistics (JSON format)'
    )
    parser.add_argument(
        '--min-cluster-size',
        type=int,
        default=100,
        help='Minimum cluster size [100]'
    )
    parser.add_argument(
        '--min-samples',
        type=int,
        default=None,
        help='Minimum samples (default: min_cluster_size)'
    )
    parser.add_argument(
        '--cluster-selection-epsilon',
        type=float,
        default=0.0,
        help='Cluster selection epsilon [0.0]'
    )
    parser.add_argument(
        '--cluster-selection-method',
        default='eom',
        choices=['eom', 'leaf'],
        help='Cluster selection method [eom]'
    )
    parser.add_argument(
        '--metric',
        default='euclidean',
        help='Distance metric [euclidean]'
    )
    parser.add_argument(
        '--random-state',
        type=int,
        default=42,
        help='Random seed for reproducibility [42]'
    )
    parser.add_argument(
        '--dimensions',
        type=str,
        default='UMAP1,UMAP2',
        help='Comma-separated dimension names to use [UMAP1,UMAP2]'
    )

    return parser.parse_args()

def load_umap_data(filename, dimensions):
    """Load UMAP coordinates."""
    df = pd.read_csv(filename, delimiter="\t")

    # Validate dimensions exist
    dim_list = [d.strip() for d in dimensions.split(',')]
    missing_dims = [d for d in dim_list if d not in df.columns]
    if missing_dims:
        raise ValueError(f"Missing dimensions in input: {missing_dims}")

    # Extract metadata and coordinates
    meta_cols = ["read", "length"]
    metadata = df[meta_cols]
    coordinates = df[dim_list]

    return metadata, coordinates, dim_list

def perform_hdbscan(coordinates, min_cluster_size, min_samples,
                    cluster_selection_epsilon, cluster_selection_method,
                    metric, random_state):
    """Perform HDBSCAN clustering."""

    # Set min_samples to min_cluster_size if not specified
    if min_samples is None:
        min_samples = min_cluster_size

    print(f"Performing HDBSCAN clustering...", file=sys.stderr)
    print(f"  min_cluster_size: {min_cluster_size}", file=sys.stderr)
    print(f"  min_samples: {min_samples}", file=sys.stderr)
    print(f"  cluster_selection_epsilon: {cluster_selection_epsilon}", file=sys.stderr)
    print(f"  cluster_selection_method: {cluster_selection_method}", file=sys.stderr)
    print(f"  metric: {metric}", file=sys.stderr)
    print(f"  random_state: {random_state}", file=sys.stderr)

    clusterer = hdbscan.HDBSCAN(
        min_cluster_size=min_cluster_size,
        min_samples=min_samples,
        cluster_selection_epsilon=cluster_selection_epsilon,
        cluster_selection_method=cluster_selection_method,
        metric=metric,
        core_dist_n_jobs=-1  # Use all cores
    )

    # Set random seed for reproducibility (numpy used internally)
    np.random.seed(random_state)

    labels = clusterer.fit_predict(coordinates)

    return labels, clusterer

def analyze_clusters(labels):
    """Analyze cluster assignments and return statistics."""

    # Count clusters
    unique_labels = np.unique(labels)
    n_clusters = len(unique_labels) - (1 if -1 in unique_labels else 0)
    n_noise = int((labels == -1).sum())  # Convert numpy int64 to Python int
    n_total = len(labels)

    # Cluster sizes
    cluster_counts = Counter(labels)
    cluster_sizes = {int(k): int(v) for k, v in cluster_counts.items() if k != -1}

    # Statistics - Convert all numpy types to Python native types for JSON serialization
    stats = {
        'n_reads': int(n_total),
        'n_clusters': int(n_clusters),
        'n_noise': n_noise,
        'noise_fraction': float(n_noise / n_total if n_total > 0 else 0),
        'cluster_sizes': cluster_sizes,
        'largest_cluster': int(max(cluster_sizes.values())) if cluster_sizes else 0,
        'smallest_cluster': int(min(cluster_sizes.values())) if cluster_sizes else 0,
        'mean_cluster_size': float(np.mean(list(cluster_sizes.values()))) if cluster_sizes else 0.0
    }

    return stats

def create_output_dataframe(metadata, coordinates, labels):
    """Create output dataframe with cluster assignments."""

    output = pd.concat([
        metadata.reset_index(drop=True),
        coordinates.reset_index(drop=True)
    ], axis=1)

    output['cluster_id'] = labels

    return output

def plot_clusters(coordinates, labels, output_file, dim_names, stats):
    """Create visualization of clustered data."""

    if len(dim_names) < 2:
        print(f"Skipping plot (need at least 2 dimensions, got {len(dim_names)})", file=sys.stderr)
        return

    # Use first two dimensions for plotting
    x_dim, y_dim = dim_names[0], dim_names[1]

    fig, ax = plt.subplots(figsize=(16, 14))
    sns.set_style("whitegrid")

    # Get unique clusters (excluding noise)
    unique_labels = sorted([l for l in np.unique(labels) if l != -1])

    # Plot noise points first (gray)
    noise_mask = labels == -1
    if noise_mask.any():
        ax.scatter(
            coordinates.loc[noise_mask, x_dim],
            coordinates.loc[noise_mask, y_dim],
            c='lightgray',
            s=1,
            alpha=0.3,
            label='Noise'
        )

    # Plot clusters with distinct colors
    if unique_labels:
        # Use a colormap with enough distinct colors
        cmap = plt.cm.get_cmap('tab20' if len(unique_labels) <= 20 else 'hsv')
        colors = [cmap(i / max(len(unique_labels), 1)) for i in range(len(unique_labels))]

        for i, cluster_id in enumerate(unique_labels):
            cluster_mask = labels == cluster_id
            cluster_size = cluster_mask.sum()

            ax.scatter(
                coordinates.loc[cluster_mask, x_dim],
                coordinates.loc[cluster_mask, y_dim],
                c=[colors[i]],
                s=3,
                alpha=0.7,
                label=f'Cluster {cluster_id} (n={cluster_size})'
            )

            # Annotate cluster with ID at centroid
            centroid_x = coordinates.loc[cluster_mask, x_dim].mean()
            centroid_y = coordinates.loc[cluster_mask, y_dim].mean()
            ax.annotate(
                str(cluster_id),
                (centroid_x, centroid_y),
                fontsize=14,
                fontweight='bold',
                ha='center',
                bbox=dict(boxstyle='round,pad=0.3', facecolor=colors[i], alpha=0.7, edgecolor='black')
            )

    ax.set_xlabel(x_dim, fontsize=14)
    ax.set_ylabel(y_dim, fontsize=14)

    title = f"HDBSCAN Clustering: {stats['n_reads']} reads → {stats['n_clusters']} clusters"
    if stats['n_noise'] > 0:
        title += f" ({stats['n_noise']} noise, {stats['noise_fraction']:.1%})"
    ax.set_title(title, fontsize=16, fontweight='bold')

    # Legend
    if len(unique_labels) <= 10:
        ax.legend(loc='upper right', fontsize=10, framealpha=0.9)

    plt.tight_layout()
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    plt.close()

    print(f"Cluster plot saved to {output_file}", file=sys.stderr)

def main():
    args = parse_args()

    # Load data
    print(f"Loading UMAP coordinates from {args.input}...", file=sys.stderr)
    metadata, coordinates, dim_names = load_umap_data(args.input, args.dimensions)
    print(f"Loaded {len(metadata)} reads with {len(dim_names)} dimensions", file=sys.stderr)

    # Perform clustering
    labels, clusterer = perform_hdbscan(
        coordinates,
        args.min_cluster_size,
        args.min_samples,
        args.cluster_selection_epsilon,
        args.cluster_selection_method,
        args.metric,
        args.random_state
    )

    # Analyze results
    stats = analyze_clusters(labels)

    print("\nClustering Results:", file=sys.stderr)
    print(f"  Total reads: {stats['n_reads']}", file=sys.stderr)
    print(f"  Clusters found: {stats['n_clusters']}", file=sys.stderr)
    print(f"  Noise points: {stats['n_noise']} ({stats['noise_fraction']:.1%})", file=sys.stderr)

    if stats['n_clusters'] > 0:
        print(f"  Largest cluster: {stats['largest_cluster']} reads", file=sys.stderr)
        print(f"  Smallest cluster: {stats['smallest_cluster']} reads", file=sys.stderr)
        print(f"  Mean cluster size: {stats['mean_cluster_size']:.1f} reads", file=sys.stderr)
    else:
        print("  WARNING: No clusters found! All points classified as noise.", file=sys.stderr)
        print("  Consider reducing min_cluster_size or adjusting other parameters.", file=sys.stderr)

    # Create output DataFrame
    output_df = create_output_dataframe(metadata, coordinates, labels)

    # Save results
    print(f"\nSaving cluster assignments to {args.output}...", file=sys.stderr)
    output_df.to_csv(args.output, sep="\t", index=False)

    # Save cluster statistics
    print(f"Saving cluster statistics to {args.cluster_info}...", file=sys.stderr)
    with open(args.cluster_info, 'w') as f:
        json.dump(stats, f, indent=2)

    # Create plot
    if args.plot:
        print(f"Creating cluster visualization...", file=sys.stderr)
        plot_clusters(coordinates, labels, args.plot, dim_names, stats)

    print("\nHDBSCAN clustering complete!", file=sys.stderr)

    # Return non-zero exit code if no clusters found
    if stats['n_clusters'] == 0:
        print("\nWARNING: Pipeline may fail if no clusters were found!", file=sys.stderr)
        return 1

    return 0

if __name__ == "__main__":
    sys.exit(main())
