#!/usr/bin/env python3
"""
Update cluster assignments for rescued noise points.

This script updates the original HDBSCAN cluster assignments by incorporating
rescued noise points from secondary vsearch clustering. It assigns new cluster
IDs to rescued reads and calculates rescue statistics.

Usage:
    update_rescued_clusters.py \\
        --clusters original_clusters.tsv \\
        --mapping rescue_mapping.txt \\
        --output updated_clusters.tsv \\
        --stats rescue_stats.json \\
        --noise-count <count>
"""

import argparse
import json
import sys
from pathlib import Path
import pandas as pd


def parse_args():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Update cluster assignments for rescued noise points"
    )
    parser.add_argument(
        "--clusters",
        type=Path,
        required=True,
        help="Original HDBSCAN clusters TSV file"
    )
    parser.add_argument(
        "--mapping",
        type=Path,
        required=True,
        help="Rescue mapping file (read_id cluster_id)"
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Output updated clusters TSV file"
    )
    parser.add_argument(
        "--stats",
        type=Path,
        required=True,
        help="Output rescue statistics JSON file"
    )
    parser.add_argument(
        "--noise-count",
        type=int,
        required=True,
        help="Total number of noise reads before rescue"
    )

    return parser.parse_args()


def load_rescue_mapping(mapping_file):
    """
    Load rescue mapping from vsearch results.

    Parameters
    ----------
    mapping_file : Path
        Path to rescue mapping file

    Returns
    -------
    dict
        Dictionary mapping read_id to new cluster_id
    """
    rescue_map = {}

    if not mapping_file.exists():
        print(f"Warning: Rescue mapping file not found: {mapping_file}", file=sys.stderr)
        return rescue_map

    with open(mapping_file, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                parts = line.split()
                if len(parts) == 2:
                    read_id, cluster_id = parts
                    rescue_map[read_id] = int(cluster_id)

    return rescue_map


def update_clusters(clusters_df, rescue_map):
    """
    Update cluster assignments for rescued reads.

    Parameters
    ----------
    clusters_df : pd.DataFrame
        Original cluster assignments
    rescue_map : dict
        Mapping of read_id to new cluster_id

    Returns
    -------
    tuple
        (updated_df, rescued_count, rescued_clusters)
    """
    rescued_count = 0

    for idx, row in clusters_df.iterrows():
        if row['cluster_id'] == -1 and row['read'] in rescue_map:
            clusters_df.at[idx, 'cluster_id'] = rescue_map[row['read']]
            rescued_count += 1

    # Count rescued clusters
    rescued_clusters = len(set(rescue_map.values())) if rescue_map else 0

    return clusters_df, rescued_count, rescued_clusters


def calculate_statistics(noise_count, rescued_count, rescued_clusters, final_noise):
    """
    Calculate rescue statistics.

    Parameters
    ----------
    noise_count : int
        Original number of noise reads
    rescued_count : int
        Number of reads successfully rescued
    rescued_clusters : int
        Number of new clusters created
    final_noise : int
        Final number of noise reads after rescue

    Returns
    -------
    dict
        Statistics dictionary
    """
    rescue_rate = round(rescued_count / noise_count * 100, 2) if noise_count > 0 else 0.0

    return {
        "noise_reads": int(noise_count),
        "rescued_clusters": int(rescued_clusters),
        "rescued_reads": int(rescued_count),
        "final_noise": int(final_noise),
        "rescue_rate": rescue_rate
    }


def main():
    """Main execution function."""
    args = parse_args()

    # Load original clusters
    print(f"Loading clusters from: {args.clusters}", file=sys.stderr)
    clusters_df = pd.read_csv(args.clusters, sep='\t')

    # Load rescue mapping
    print(f"Loading rescue mapping from: {args.mapping}", file=sys.stderr)
    rescue_map = load_rescue_mapping(args.mapping)

    # Update cluster assignments
    print(f"Updating cluster assignments for {len(rescue_map)} rescued reads", file=sys.stderr)
    clusters_df, rescued_count, rescued_clusters = update_clusters(clusters_df, rescue_map)

    # Calculate final noise count
    final_noise = (clusters_df['cluster_id'] == -1).sum()

    # Save updated clusters
    print(f"Saving updated clusters to: {args.output}", file=sys.stderr)
    clusters_df.to_csv(args.output, sep='\t', index=False)

    # Calculate and save statistics
    stats = calculate_statistics(
        args.noise_count,
        rescued_count,
        rescued_clusters,
        final_noise
    )

    print(f"Saving statistics to: {args.stats}", file=sys.stderr)
    with open(args.stats, 'w') as f:
        json.dump(stats, f, indent=2)

    # Print summary
    print(
        f"Rescued {rescued_count}/{args.noise_count} noise reads "
        f"into {rescued_clusters} new clusters "
        f"({stats['rescue_rate']}% rescue rate)",
        file=sys.stderr
    )
    print(f"Final noise reads: {final_noise}", file=sys.stderr)


if __name__ == "__main__":
    main()
