#!/usr/bin/env python3
"""
Combine classification results from multiple classifiers (KRAKEN2, BLAST, FastANI)
and determine consensus classification with confidence assessment.
"""

import argparse
import json
import csv
import sys
from pathlib import Path
from collections import defaultdict


def parse_args():
    parser = argparse.ArgumentParser(
        description='Combine multiple classification results'
    )
    parser.add_argument(
        '-k', '--kraken2',
        help='KRAKEN2 report file',
        type=str
    )
    parser.add_argument(
        '-b', '--blast',
        help='BLAST results file (CSV format)',
        type=str
    )
    parser.add_argument(
        '-f', '--fastani',
        help='FastANI results file',
        type=str
    )
    parser.add_argument(
        '-o', '--output-prefix',
        help='Output file prefix',
        required=True,
        type=str
    )
    parser.add_argument(
        '--sample-id',
        help='Sample ID',
        required=True,
        type=str
    )
    parser.add_argument(
        '--cluster-id',
        help='Cluster ID',
        required=True,
        type=str
    )
    parser.add_argument(
        '--min-blast-identity',
        help='Minimum BLAST identity threshold',
        type=float,
        default=80.0
    )
    parser.add_argument(
        '--min-ani-similarity',
        help='Minimum ANI similarity threshold',
        type=float,
        default=95.0
    )

    return parser.parse_args()


def parse_kraken2(filepath):
    """Parse KRAKEN2 classification output"""
    classification = {
        'classified': False,
        'taxid': None,
        'name': 'Unclassified',
        'confidence': 0.0,
        'reads': 0
    }

    if not filepath or not Path(filepath).exists():
        return classification

    try:
        with open(filepath) as f:
            for line in f:
                # KRAKEN2 report format: C/U readID taxID length classification
                parts = line.strip().split('\t')
                if len(parts) >= 3 and parts[0] == 'C':
                    classification['classified'] = True
                    classification['taxid'] = parts[2]
                    classification['name'] = parts[-1].strip() if len(parts) > 4 else 'Unknown'
                    classification['confidence'] = 1.0  # Simplified - could parse actual confidence
                    classification['reads'] = 1
                    break
    except Exception as e:
        print(f"Warning: Could not parse KRAKEN2 file: {e}", file=sys.stderr)

    return classification


def parse_blast(filepath, min_identity):
    """Parse BLAST output (CSV format)"""
    hits = []

    if not filepath or not Path(filepath).exists():
        return {
            'classified': False,
            'taxid': None,
            'name': 'No BLAST results',
            'identity': 0.0,
            'num_hits': 0
        }

    try:
        with open(filepath) as f:
            reader = csv.reader(f)
            for row in reader:
                # Expected format: staxids, sscinames, evalue, length, score, pident
                if len(row) >= 6:
                    try:
                        hit = {
                            'taxid': row[0],
                            'name': row[1],
                            'evalue': float(row[2]),
                            'length': int(row[3]),
                            'score': float(row[4]),
                            'identity': float(row[5])
                        }

                        # Filter by threshold
                        if hit['identity'] >= min_identity:
                            hits.append(hit)
                    except (ValueError, IndexError) as e:
                        continue
    except Exception as e:
        print(f"Warning: Could not parse BLAST file: {e}", file=sys.stderr)

    # Return best hit
    if hits:
        best_hit = max(hits, key=lambda x: (x['identity'], x['score']))
        return {
            'classified': True,
            'taxid': best_hit['taxid'],
            'name': best_hit['name'],
            'identity': best_hit['identity'],
            'evalue': best_hit['evalue'],
            'score': best_hit['score'],
            'num_hits': len(hits)
        }
    else:
        return {
            'classified': False,
            'taxid': None,
            'name': 'No significant BLAST hits',
            'identity': 0.0,
            'num_hits': 0
        }


def parse_fastani(filepath, min_similarity):
    """Parse FastANI output"""
    hits = []

    if not filepath or not Path(filepath).exists():
        return {
            'classified': False,
            'reference': None,
            'ani': 0.0,
            'num_hits': 0
        }

    try:
        with open(filepath) as f:
            for line in f:
                parts = line.strip().split('\t')
                if len(parts) >= 5:
                    try:
                        hit = {
                            'reference': Path(parts[0]).stem,
                            'query': Path(parts[1]).stem,
                            'ani': float(parts[2]),
                            'fragments_aligned': int(parts[3]),
                            'total_fragments': int(parts[4])
                        }

                        if hit['ani'] >= min_similarity:
                            hits.append(hit)
                    except (ValueError, IndexError):
                        continue
    except Exception as e:
        print(f"Warning: Could not parse FastANI file: {e}", file=sys.stderr)

    if hits:
        best_hit = max(hits, key=lambda x: x['ani'])
        return {
            'classified': True,
            'reference': best_hit['reference'],
            'ani': best_hit['ani'],
            'fragments_aligned': best_hit['fragments_aligned'],
            'total_fragments': best_hit['total_fragments'],
            'coverage': best_hit['fragments_aligned'] / best_hit['total_fragments'] * 100,
            'num_hits': len(hits)
        }
    else:
        return {
            'classified': False,
            'reference': None,
            'ani': 0.0,
            'num_hits': 0
        }


def determine_consensus(classifications):
    """Determine consensus classification from multiple methods"""
    # Priority: BLAST > KRAKEN2 > FastANI
    # (BLAST typically more specific for 16S/18S classification)

    if 'blast' in classifications and classifications['blast']['classified']:
        return {
            'method': 'BLAST',
            'taxid': classifications['blast']['taxid'],
            'name': classifications['blast']['name'],
            'identity': classifications['blast']['identity'],
            'source': 'blast'
        }

    if 'kraken2' in classifications and classifications['kraken2']['classified']:
        return {
            'method': 'KRAKEN2',
            'taxid': classifications['kraken2']['taxid'],
            'name': classifications['kraken2']['name'],
            'confidence': classifications['kraken2']['confidence'],
            'source': 'kraken2'
        }

    if 'fastani' in classifications and classifications['fastani']['classified']:
        return {
            'method': 'FastANI',
            'reference': classifications['fastani']['reference'],
            'ani': classifications['fastani']['ani'],
            'coverage': classifications['fastani']['coverage'],
            'source': 'fastani'
        }

    return {
        'method': 'None',
        'classification': 'Unclassified',
        'reason': 'No significant matches in any classifier',
        'source': 'none'
    }


def calculate_confidence(classifications):
    """Calculate overall confidence based on agreement and classifier performance"""
    classified_count = sum(1 for c in classifications.values()
                          if c.get('classified', False))
    total_classifiers = len(classifications)

    if classified_count == 0:
        return 'none'
    elif classified_count == total_classifiers:
        return 'high'
    elif classified_count >= total_classifiers / 2:
        return 'medium'
    else:
        return 'low'


def write_csv(filename, results):
    """Write CSV output"""
    with open(filename, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow([
            'Sample', 'Cluster', 'Method', 'Classification',
            'Confidence', 'TaxID', 'Details'
        ])

        consensus = results['consensus']

        writer.writerow([
            results['meta']['id'],
            results['meta']['cluster_id'],
            consensus.get('method', 'None'),
            consensus.get('name', consensus.get('classification', consensus.get('reference', 'Unknown'))),
            results['confidence'],
            consensus.get('taxid', ''),
            json.dumps(consensus)
        ])


def write_json(filename, results):
    """Write JSON output"""
    with open(filename, 'w') as f:
        json.dump(results, f, indent=2)


def write_combined(filename, results):
    """Write human-readable combined output"""
    with open(filename, 'w') as f:
        f.write(f"Classification Results for {results['meta']['id']} ")
        f.write(f"Cluster {results['meta']['cluster_id']}\n")
        f.write("=" * 70 + "\n\n")

        for method, result in results['classifications'].items():
            f.write(f"{method.upper()}:\n")
            f.write(f"  Classified: {result.get('classified', False)}\n")

            if result.get('classified'):
                for key, value in result.items():
                    if key != 'classified':
                        f.write(f"  {key}: {value}\n")

            f.write("\n")

        f.write("CONSENSUS:\n")
        for key, value in results['consensus'].items():
            f.write(f"  {key}: {value}\n")

        f.write(f"\nOverall Confidence: {results['confidence']}\n")


def main():
    args = parse_args()

    # Parse classification results
    classifications = {}

    if args.kraken2:
        classifications['kraken2'] = parse_kraken2(args.kraken2)
        print(f"KRAKEN2: {classifications['kraken2']}", file=sys.stderr)

    if args.blast:
        classifications['blast'] = parse_blast(args.blast, args.min_blast_identity)
        print(f"BLAST: {classifications['blast']}", file=sys.stderr)

    if args.fastani:
        classifications['fastani'] = parse_fastani(args.fastani, args.min_ani_similarity)
        print(f"FastANI: {classifications['fastani']}", file=sys.stderr)

    # Determine consensus classification
    consensus = determine_consensus(classifications)
    confidence = calculate_confidence(classifications)

    # Build results structure
    results = {
        'meta': {
            'id': args.sample_id,
            'cluster_id': args.cluster_id
        },
        'classifications': classifications,
        'consensus': consensus,
        'confidence': confidence
    }

    # Write outputs
    write_csv(f'{args.output_prefix}_classification.csv', results)
    write_json(f'{args.output_prefix}_classification.json', results)
    write_combined(f'{args.output_prefix}_combined.txt', results)

    print(f"✓ Classification complete: {consensus.get('name', consensus.get('classification', 'Unknown'))}",
          file=sys.stderr)
    print(f"  Method: {consensus['method']}", file=sys.stderr)
    print(f"  Confidence: {confidence}", file=sys.stderr)


if __name__ == '__main__':
    main()
