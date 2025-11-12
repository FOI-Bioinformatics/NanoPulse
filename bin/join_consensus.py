#!/usr/bin/env python3
"""
Join consensus sequences from multiple clusters with taxonomic annotations.

This script merges consensus sequences from all clusters into a single FASTA file,
adding taxonomic classification information to the headers and creating comprehensive
annotation files.
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, List, Tuple


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
            "confidence": 0.0,
            "methods": []
        }

    try:
        with open(classification_file, 'r') as f:
            data = json.load(f)
            return {
                "taxon": data.get("consensus_taxon", "Unclassified"),
                "rank": data.get("consensus_rank", "unknown"),
                "confidence": data.get("confidence", 0.0),
                "methods": data.get("classification_methods", [])
            }
    except (json.JSONDecodeError, KeyError) as e:
        print(f"Warning: Could not parse {classification_file}: {e}", file=sys.stderr)
        return {
            "taxon": "Unclassified",
            "rank": "unknown",
            "confidence": 0.0,
            "methods": []
        }


def parse_fasta(fasta_file: Path) -> List[Tuple[str, str]]:
    """
    Parse FASTA file and return list of (header, sequence) tuples.

    Args:
        fasta_file: Path to FASTA file

    Returns:
        List of (header, sequence) tuples
    """
    sequences = []
    current_header = None
    current_seq = []

    with open(fasta_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            if line.startswith('>'):
                # Save previous sequence
                if current_header is not None:
                    sequences.append((current_header, ''.join(current_seq)))

                # Start new sequence
                current_header = line[1:]  # Remove '>'
                current_seq = []
            else:
                current_seq.append(line)

        # Save last sequence
        if current_header is not None:
            sequences.append((current_header, ''.join(current_seq)))

    return sequences


def extract_cluster_id(filename: str) -> int:
    """
    Extract cluster ID from filename.

    Args:
        filename: Consensus filename (e.g., "sample_cluster0_consensus.fasta")

    Returns:
        Cluster ID as integer
    """
    # Try to extract cluster ID from filename
    # Expected format: *_cluster<N>_* or *_cluster_<N>_*
    import re
    match = re.search(r'cluster[_]?(\d+)', filename, re.IGNORECASE)
    if match:
        return int(match.group(1))

    # Fallback: use filename as-is
    return -1


def join_consensus_sequences(
    consensus_files: List[Path],
    classification_files: List[Path],
    output_fasta: Path,
    output_tsv: Path,
    output_json: Path
) -> None:
    """
    Join consensus sequences with classifications.

    Args:
        consensus_files: List of consensus FASTA files
        classification_files: List of classification JSON files
        output_fasta: Output FASTA file path
        output_tsv: Output TSV annotations file path
        output_json: Output JSON summary file path
    """
    # Create mapping of cluster IDs to files
    cluster_data = []

    for cons_file, class_file in zip(consensus_files, classification_files):
        cluster_id = extract_cluster_id(cons_file.name)

        # Parse classification
        classification = parse_classification(class_file)

        # Parse consensus sequence
        sequences = parse_fasta(cons_file)

        if not sequences:
            print(f"Warning: No sequences found in {cons_file}", file=sys.stderr)
            continue

        # Use first sequence (should only be one consensus per cluster)
        header, sequence = sequences[0]

        cluster_data.append({
            'cluster_id': cluster_id,
            'original_header': header,
            'sequence': sequence,
            'length': len(sequence),
            'taxon': classification['taxon'],
            'rank': classification['rank'],
            'confidence': classification['confidence'],
            'methods': classification['methods']
        })

    # Sort by cluster ID
    cluster_data.sort(key=lambda x: x['cluster_id'])

    # Write merged FASTA with annotated headers
    with open(output_fasta, 'w') as f:
        for data in cluster_data:
            # Create informative header
            header = (
                f"cluster_{data['cluster_id']} "
                f"taxon={data['taxon']} "
                f"rank={data['rank']} "
                f"confidence={data['confidence']:.2f} "
                f"length={data['length']} "
                f"methods={','.join(data['methods']) if data['methods'] else 'none'}"
            )

            f.write(f">{header}\n")

            # Write sequence with line wrapping (80 chars)
            seq = data['sequence']
            for i in range(0, len(seq), 80):
                f.write(f"{seq[i:i+80]}\n")

    # Write TSV annotations
    with open(output_tsv, 'w') as f:
        # Header
        f.write("cluster_id\ttaxon\rank\tconfidence\tlength\tmethods\toriginal_header\n")

        # Data rows
        for data in cluster_data:
            f.write(
                f"{data['cluster_id']}\t"
                f"{data['taxon']}\t"
                f"{data['rank']}\t"
                f"{data['confidence']:.4f}\t"
                f"{data['length']}\t"
                f"{','.join(data['methods']) if data['methods'] else 'none'}\t"
                f"{data['original_header']}\n"
            )

    # Create summary statistics
    summary = {
        'total_clusters': len(cluster_data),
        'total_bases': sum(d['length'] for d in cluster_data),
        'mean_length': sum(d['length'] for d in cluster_data) / len(cluster_data) if cluster_data else 0,
        'min_length': min(d['length'] for d in cluster_data) if cluster_data else 0,
        'max_length': max(d['length'] for d in cluster_data) if cluster_data else 0,
        'classified': sum(1 for d in cluster_data if d['taxon'] != 'Unclassified'),
        'unclassified': sum(1 for d in cluster_data if d['taxon'] == 'Unclassified'),
        'classification_rate': (
            sum(1 for d in cluster_data if d['taxon'] != 'Unclassified') / len(cluster_data) * 100
            if cluster_data else 0
        ),
        'mean_confidence': (
            sum(d['confidence'] for d in cluster_data) / len(cluster_data)
            if cluster_data else 0
        )
    }

    # Add taxonomy breakdown
    taxa = {}
    for data in cluster_data:
        taxon = data['taxon']
        if taxon not in taxa:
            taxa[taxon] = 0
        taxa[taxon] += 1

    summary['taxa_counts'] = taxa
    summary['unique_taxa'] = len(taxa)

    # Write JSON summary
    with open(output_json, 'w') as f:
        json.dump(summary, f, indent=2)

    # Print summary to stdout
    print(f"Joined {summary['total_clusters']} consensus sequences")
    print(f"Total bases: {summary['total_bases']:,}")
    print(f"Mean length: {summary['mean_length']:.1f} bp")
    print(f"Classification rate: {summary['classification_rate']:.1f}%")
    print(f"Unique taxa: {summary['unique_taxa']}")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Join consensus sequences with taxonomic annotations"
    )

    parser.add_argument(
        '--consensus',
        nargs='+',
        required=True,
        help='Consensus FASTA files'
    )

    parser.add_argument(
        '--classifications',
        nargs='+',
        required=True,
        help='Classification JSON files'
    )

    parser.add_argument(
        '--output_fasta',
        type=Path,
        required=True,
        help='Output merged FASTA file'
    )

    parser.add_argument(
        '--output_tsv',
        type=Path,
        required=True,
        help='Output TSV annotations file'
    )

    parser.add_argument(
        '--output_json',
        type=Path,
        required=True,
        help='Output JSON summary file'
    )

    args = parser.parse_args()

    # Convert to Path objects
    consensus_files = [Path(f) for f in args.consensus]
    classification_files = [Path(f) for f in args.classifications]

    # Validate inputs
    if len(consensus_files) != len(classification_files):
        print(
            f"Error: Number of consensus files ({len(consensus_files)}) does not match "
            f"number of classification files ({len(classification_files)})",
            file=sys.stderr
        )
        sys.exit(1)

    # Check files exist
    for f in consensus_files:
        if not f.exists():
            print(f"Error: Consensus file not found: {f}", file=sys.stderr)
            sys.exit(1)

    for f in classification_files:
        if not f.exists():
            print(f"Warning: Classification file not found: {f}", file=sys.stderr)

    # Join sequences
    join_consensus_sequences(
        consensus_files,
        classification_files,
        args.output_fasta,
        args.output_tsv,
        args.output_json
    )


if __name__ == '__main__':
    main()
