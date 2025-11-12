#!/usr/bin/env python3
"""
Calculate cluster abundances and diversity metrics.

This script calculates:
- Relative abundances for each cluster
- Taxonomic abundance summaries
- Alpha diversity metrics (Shannon, Simpson, effective species)
"""

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Dict, List, Tuple


def parse_cluster_stats(stats_file: Path) -> Dict[int, int]:
    """
    Parse cluster statistics JSON to get read counts per cluster.

    Args:
        stats_file: Path to cluster_stats.json

    Returns:
        Dictionary mapping cluster_id -> read_count
    """
    with open(stats_file, 'r') as f:
        data = json.load(f)

    cluster_counts = {}
    for cluster in data.get('clusters', []):
        cluster_id = cluster.get('cluster_id', -1)
        read_count = cluster.get('read_count', 0)
        cluster_counts[cluster_id] = read_count

    return cluster_counts


def parse_classification(classification_file: Path) -> Dict:
    """
    Parse classification JSON file.

    Args:
        classification_file: Path to classification JSON

    Returns:
        Dictionary with classification information
    """
    if not classification_file.exists():
        return {
            "taxon": "Unclassified",
            "rank": "unknown",
            "confidence": 0.0
        }

    try:
        with open(classification_file, 'r') as f:
            data = json.load(f)
            return {
                "taxon": data.get("consensus_taxon", "Unclassified"),
                "rank": data.get("consensus_rank", "unknown"),
                "confidence": data.get("confidence", 0.0)
            }
    except (json.JSONDecodeError, KeyError) as e:
        print(f"Warning: Could not parse {classification_file}: {e}", file=sys.stderr)
        return {
            "taxon": "Unclassified",
            "rank": "unknown",
            "confidence": 0.0
        }


def extract_cluster_id(filename: str) -> int:
    """
    Extract cluster ID from filename.

    Args:
        filename: Classification filename

    Returns:
        Cluster ID as integer
    """
    import re
    match = re.search(r'cluster[_]?(\d+)', filename, re.IGNORECASE)
    if match:
        return int(match.group(1))
    return -1


def calculate_shannon_diversity(abundances: List[float]) -> float:
    """
    Calculate Shannon diversity index.

    H' = -sum(p_i * ln(p_i))

    Args:
        abundances: List of relative abundances (proportions)

    Returns:
        Shannon diversity index
    """
    shannon = 0.0
    for p in abundances:
        if p > 0:
            shannon -= p * math.log(p)
    return shannon


def calculate_simpson_diversity(abundances: List[float]) -> float:
    """
    Calculate Simpson diversity index (1 - D).

    D = sum(p_i^2)
    Simpson = 1 - D

    Args:
        abundances: List of relative abundances (proportions)

    Returns:
        Simpson diversity index (1-D)
    """
    simpson_d = sum(p * p for p in abundances)
    return 1.0 - simpson_d


def calculate_effective_species(abundances: List[float], method: str = 'shannon') -> float:
    """
    Calculate effective number of species (Hill numbers).

    For Shannon: exp(H')
    For Simpson: 1/D

    Args:
        abundances: List of relative abundances (proportions)
        method: 'shannon' or 'simpson'

    Returns:
        Effective number of species
    """
    if method == 'shannon':
        h = calculate_shannon_diversity(abundances)
        return math.exp(h)
    elif method == 'simpson':
        simpson_d = sum(p * p for p in abundances)
        return 1.0 / simpson_d if simpson_d > 0 else 0.0
    else:
        raise ValueError(f"Unknown method: {method}")


def calculate_abundances(
    cluster_stats_file: Path,
    classification_files: List[Path],
    output_csv: Path,
    output_diversity: Path,
    output_json: Path
) -> None:
    """
    Calculate cluster abundances and diversity metrics.

    Args:
        cluster_stats_file: Path to cluster_stats.json
        classification_files: List of classification JSON files
        output_csv: Output CSV file path
        output_diversity: Output diversity metrics text file
        output_json: Output JSON summary file path
    """
    # Parse cluster read counts
    cluster_counts = parse_cluster_stats(cluster_stats_file)

    # Parse classifications
    cluster_taxa = {}
    for class_file in classification_files:
        cluster_id = extract_cluster_id(class_file.name)
        classification = parse_classification(class_file)
        cluster_taxa[cluster_id] = classification

    # Calculate total reads
    total_reads = sum(cluster_counts.values())

    if total_reads == 0:
        print("Warning: No reads found in clusters", file=sys.stderr)
        total_reads = 1  # Avoid division by zero

    # Calculate relative abundances
    cluster_data = []
    for cluster_id in sorted(cluster_counts.keys()):
        read_count = cluster_counts[cluster_id]
        relative_abundance = read_count / total_reads

        classification = cluster_taxa.get(cluster_id, {
            "taxon": "Unclassified",
            "rank": "unknown",
            "confidence": 0.0
        })

        cluster_data.append({
            'cluster_id': cluster_id,
            'read_count': read_count,
            'relative_abundance': relative_abundance,
            'taxon': classification['taxon'],
            'rank': classification['rank'],
            'confidence': classification['confidence']
        })

    # Write CSV abundances
    with open(output_csv, 'w') as f:
        f.write("cluster_id,read_count,relative_abundance,taxon,rank,confidence\n")
        for data in cluster_data:
            f.write(
                f"{data['cluster_id']},"
                f"{data['read_count']},"
                f"{data['relative_abundance']:.6f},"
                f"{data['taxon']},"
                f"{data['rank']},"
                f"{data['confidence']:.4f}\n"
            )

    # Calculate diversity metrics
    abundances = [d['relative_abundance'] for d in cluster_data]

    shannon = calculate_shannon_diversity(abundances)
    simpson = calculate_simpson_diversity(abundances)
    effective_species_shannon = calculate_effective_species(abundances, 'shannon')
    effective_species_simpson = calculate_effective_species(abundances, 'simpson')

    # Write diversity metrics
    with open(output_diversity, 'w') as f:
        f.write("=" * 70 + "\n")
        f.write("DIVERSITY METRICS\n")
        f.write("=" * 70 + "\n\n")

        f.write(f"Total clusters: {len(cluster_data)}\n")
        f.write(f"Total reads: {total_reads:,}\n\n")

        f.write("Alpha Diversity:\n")
        f.write(f"  Shannon diversity (H'):        {shannon:.4f}\n")
        f.write(f"  Simpson diversity (1-D):       {simpson:.4f}\n")
        f.write(f"  Effective species (exp(H')):   {effective_species_shannon:.2f}\n")
        f.write(f"  Effective species (1/D):       {effective_species_simpson:.2f}\n\n")

        f.write("Interpretation:\n")
        f.write("  - Shannon H' typically ranges from 0 (no diversity) to ~4.5 (high diversity)\n")
        f.write("  - Simpson 1-D ranges from 0 (no diversity) to 1 (infinite diversity)\n")
        f.write("  - Effective species is the equivalent number of equally abundant species\n\n")

    # Aggregate by taxon
    taxon_counts = {}
    taxon_reads = {}
    for data in cluster_data:
        taxon = data['taxon']
        if taxon not in taxon_counts:
            taxon_counts[taxon] = 0
            taxon_reads[taxon] = 0
        taxon_counts[taxon] += 1
        taxon_reads[taxon] += data['read_count']

    # Calculate taxon abundances
    taxon_abundances = []
    for taxon in sorted(taxon_reads.keys(), key=lambda x: taxon_reads[x], reverse=True):
        taxon_abundances.append({
            'taxon': taxon,
            'cluster_count': taxon_counts[taxon],
            'read_count': taxon_reads[taxon],
            'relative_abundance': taxon_reads[taxon] / total_reads
        })

    # Create summary
    summary = {
        'total_clusters': len(cluster_data),
        'total_reads': total_reads,
        'diversity_metrics': {
            'shannon': shannon,
            'simpson': simpson,
            'effective_species_shannon': effective_species_shannon,
            'effective_species_simpson': effective_species_simpson
        },
        'cluster_abundances': cluster_data,
        'taxon_abundances': taxon_abundances,
        'unique_taxa': len(taxon_counts)
    }

    # Write JSON summary
    with open(output_json, 'w') as f:
        json.dump(summary, f, indent=2)

    # Print summary
    print(f"Total clusters: {len(cluster_data)}")
    print(f"Total reads: {total_reads:,}")
    print(f"Shannon diversity: {shannon:.4f}")
    print(f"Simpson diversity: {simpson:.4f}")
    print(f"Effective species: {effective_species_shannon:.2f}")
    print(f"Unique taxa: {len(taxon_counts)}")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Calculate cluster abundances and diversity metrics"
    )

    parser.add_argument(
        '--cluster_stats',
        type=Path,
        required=True,
        help='Cluster statistics JSON file'
    )

    parser.add_argument(
        '--classifications',
        nargs='+',
        required=True,
        help='Classification JSON files'
    )

    parser.add_argument(
        '--output_csv',
        type=Path,
        required=True,
        help='Output CSV file with cluster abundances'
    )

    parser.add_argument(
        '--output_diversity',
        type=Path,
        required=True,
        help='Output text file with diversity metrics'
    )

    parser.add_argument(
        '--output_json',
        type=Path,
        required=True,
        help='Output JSON summary file'
    )

    args = parser.parse_args()

    # Convert to Path objects
    classification_files = [Path(f) for f in args.classifications]

    # Validate inputs
    if not args.cluster_stats.exists():
        print(f"Error: Cluster stats file not found: {args.cluster_stats}", file=sys.stderr)
        sys.exit(1)

    for f in classification_files:
        if not f.exists():
            print(f"Warning: Classification file not found: {f}", file=sys.stderr)

    # Calculate abundances
    calculate_abundances(
        args.cluster_stats,
        classification_files,
        args.output_csv,
        args.output_diversity,
        args.output_json
    )


if __name__ == '__main__':
    main()
