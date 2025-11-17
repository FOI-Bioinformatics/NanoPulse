#!/usr/bin/env python3
"""
Probabilistic consensus classification using EM algorithm (Emu-inspired approach)

This script implements an expectation-maximization (EM) algorithm to assign probabilistic
taxonomic classifications to consensus sequences. Unlike simple voting-based approaches,
this method:

1. Uses Bayes' theorem to calculate P(taxon|consensus) for all candidate taxa
2. Iteratively refines taxonomic abundance estimates F(taxon) until convergence
3. Assigns confidence scores based on posterior probabilities
4. Identifies potentially novel organisms (low-confidence classifications)

Algorithm:
---------
E-step: Calculate P(taxon|consensus) = P(consensus|taxon) * F(taxon) / normalization
M-step: Update F(taxon) based on weighted assignments across all consensus sequences
Iterate until convergence (max 50 iterations, tolerance 1e-6)

Reference:
---------
Inspired by Emu (Forbes et al. 2018) - Expectation-Maximization for Microbiome Profiling
https://github.com/treangenlab/emu

Authors: FOI-Bioinformatics
License: MIT
"""

import sys
import argparse
import csv
import json
from pathlib import Path
from collections import defaultdict
import math


def parse_args():
    """Parse command-line arguments"""
    parser = argparse.ArgumentParser(
        description='Probabilistic consensus classification using EM algorithm'
    )

    parser.add_argument('--sample-id', required=True,
                       help='Sample identifier')
    parser.add_argument('--cluster-id', required=True, type=int,
                       help='Cluster identifier')
    parser.add_argument('--output-prefix', required=True,
                       help='Output file prefix')

    # Classification inputs (optional - at least one required)
    parser.add_argument('--kraken2', help='KRAKEN2 classification file')
    parser.add_argument('--blast', help='BLAST results file (CSV)')
    parser.add_argument('--fastani', help='FastANI results file')

    # Thresholds
    parser.add_argument('--min-blast-identity', type=float, default=70.0,
                       help='Minimum BLAST identity percentage (default: 70.0)')
    parser.add_argument('--min-ani-similarity', type=float, default=80.0,
                       help='Minimum FastANI similarity percentage (default: 80.0)')
    parser.add_argument('--min-kraken2-confidence', type=float, default=0.1,
                       help='Minimum KRAKEN2 confidence (default: 0.1)')

    # EM algorithm parameters
    parser.add_argument('--max-em-iterations', type=int, default=50,
                       help='Maximum EM iterations (default: 50)')
    parser.add_argument('--em-convergence-threshold', type=float, default=1e-6,
                       help='EM convergence threshold (default: 1e-6)')
    parser.add_argument('--novelty-threshold', type=float, default=0.5,
                       help='Confidence threshold for novelty detection (default: 0.5)')

    return parser.parse_args()


def parse_kraken2(filepath, min_confidence):
    """Parse KRAKEN2 output and extract candidate taxa"""
    candidates = []

    if not filepath or not Path(filepath).exists():
        return candidates

    try:
        with open(filepath) as f:
            for line in f:
                parts = line.strip().split('\t')
                if len(parts) >= 5:
                    classified = parts[0]
                    taxid = parts[2]
                    confidence = float(parts[3]) if parts[3] else 0.0
                    taxname = parts[4].strip()

                    if classified == 'C' and confidence >= min_confidence:
                        candidates.append({
                            'source': 'kraken2',
                            'taxid': taxid,
                            'name': taxname,
                            'confidence': confidence,
                            'likelihood': confidence  # Use confidence as likelihood
                        })
    except Exception as e:
        print(f"Warning: Could not parse KRAKEN2 file: {e}", file=sys.stderr)

    return candidates


def parse_blast(filepath, min_identity):
    """Parse BLAST output and extract candidate taxa"""
    candidates = []

    if not filepath or not Path(filepath).exists():
        return candidates

    try:
        with open(filepath) as f:
            reader = csv.reader(f)
            for row in reader:
                # Expected format: staxids, sscinames, evalue, length, score, pident
                if len(row) >= 6:
                    try:
                        taxid = row[0]
                        name = row[1]
                        evalue = float(row[2])
                        length = int(row[3])
                        score = float(row[4])
                        identity = float(row[5])

                        if identity >= min_identity:
                            # Calculate likelihood from identity and e-value
                            # Higher identity = higher likelihood
                            # Lower e-value = higher likelihood
                            likelihood = identity / 100.0 * (1.0 / (1.0 + evalue))

                            candidates.append({
                                'source': 'blast',
                                'taxid': taxid,
                                'name': name,
                                'identity': identity,
                                'evalue': evalue,
                                'score': score,
                                'likelihood': likelihood
                            })
                    except (ValueError, IndexError):
                        continue
    except Exception as e:
        print(f"Warning: Could not parse BLAST file: {e}", file=sys.stderr)

    return candidates


def parse_fastani(filepath, min_similarity):
    """Parse FastANI output and extract candidate taxa"""
    candidates = []

    if not filepath or not Path(filepath).exists():
        return candidates

    try:
        with open(filepath) as f:
            for line in f:
                parts = line.strip().split('\t')
                if len(parts) >= 5:
                    try:
                        reference = Path(parts[0]).stem
                        ani = float(parts[2])
                        fragments_aligned = int(parts[3])
                        total_fragments = int(parts[4])
                        coverage = fragments_aligned / total_fragments

                        if ani >= min_similarity:
                            # Calculate likelihood from ANI and coverage
                            likelihood = (ani / 100.0) * coverage

                            candidates.append({
                                'source': 'fastani',
                                'reference': reference,
                                'name': reference,
                                'ani': ani,
                                'coverage': coverage * 100,
                                'likelihood': likelihood
                            })
                    except (ValueError, IndexError, ZeroDivisionError):
                        continue
    except Exception as e:
        print(f"Warning: Could not parse FastANI file: {e}", file=sys.stderr)

    return candidates


def merge_candidates(all_candidates):
    """
    Merge candidates from multiple sources into unified taxa

    Strategy:
    - Group by taxid (BLAST/KRAKEN2) or reference name (FastANI)
    - Combine likelihoods from multiple sources for same taxon
    - Keep metadata from highest-likelihood source
    """
    taxon_map = defaultdict(lambda: {'sources': [], 'likelihoods': [], 'metadata': None})

    for candidate in all_candidates:
        # Use taxid if available, otherwise reference/name
        key = candidate.get('taxid') or candidate.get('reference') or candidate.get('name')

        if not key:
            continue

        taxon_map[key]['sources'].append(candidate['source'])
        taxon_map[key]['likelihoods'].append(candidate['likelihood'])

        # Keep metadata from highest-likelihood source
        if not taxon_map[key]['metadata'] or candidate['likelihood'] > taxon_map[key]['metadata']['likelihood']:
            taxon_map[key]['metadata'] = candidate

    # Create merged candidate list
    merged = []
    for taxon_key, data in taxon_map.items():
        # Average likelihoods from multiple sources (conservative approach)
        avg_likelihood = sum(data['likelihoods']) / len(data['likelihoods'])

        merged_candidate = data['metadata'].copy()
        merged_candidate['merged_likelihood'] = avg_likelihood
        merged_candidate['num_sources'] = len(data['sources'])
        merged_candidate['all_sources'] = ','.join(data['sources'])

        merged.append(merged_candidate)

    return merged


def initialize_priors(candidates):
    """Initialize uniform priors F(taxon) for all candidate taxa"""
    if not candidates:
        return {}

    # Uniform prior: equal probability for all candidates
    n = len(candidates)
    return {i: 1.0 / n for i in range(n)}


def em_step(candidates, priors):
    """
    Perform one EM iteration

    E-step: Calculate P(taxon|consensus) for each candidate
    M-step: Update F(taxon) based on posterior probabilities

    Returns:
    - posteriors: Dictionary mapping candidate index to P(taxon|consensus)
    - new_priors: Updated F(taxon) estimates
    """
    # E-step: Calculate unnormalized posteriors
    # P(taxon|consensus) ∝ P(consensus|taxon) * F(taxon)
    unnormalized_posteriors = {}

    for i, candidate in enumerate(candidates):
        likelihood = candidate.get('merged_likelihood', candidate.get('likelihood', 0.0))
        prior = priors.get(i, 0.0)

        # Posterior ∝ likelihood × prior
        unnormalized_posteriors[i] = likelihood * prior

    # Normalize posteriors
    total = sum(unnormalized_posteriors.values())

    if total == 0:
        # No valid candidates - return uniform
        posteriors = {i: 1.0 / len(candidates) for i in range(len(candidates))}
    else:
        posteriors = {i: p / total for i, p in unnormalized_posteriors.items()}

    # M-step: Update priors
    # In single-consensus case, posteriors = new priors
    # (In multi-consensus case, we'd aggregate across all consensus sequences)
    new_priors = posteriors.copy()

    return posteriors, new_priors


def run_em_algorithm(candidates, max_iterations, convergence_threshold):
    """
    Run EM algorithm until convergence

    Returns:
    - final_posteriors: P(taxon|consensus) for each candidate
    - iterations: Number of iterations performed
    - converged: Whether algorithm converged
    """
    if not candidates:
        return {}, 0, False

    # Initialize
    priors = initialize_priors(candidates)

    for iteration in range(max_iterations):
        # Perform EM step
        posteriors, new_priors = em_step(candidates, priors)

        # Check convergence
        max_change = max(abs(new_priors[i] - priors[i]) for i in range(len(candidates)))

        if max_change < convergence_threshold:
            print(f"EM converged after {iteration + 1} iterations (max_change={max_change:.2e})",
                  file=sys.stderr)
            return posteriors, iteration + 1, True

        # Update priors for next iteration
        priors = new_priors

    print(f"EM reached max iterations ({max_iterations}) without convergence", file=sys.stderr)
    return posteriors, max_iterations, False


def determine_classification(candidates, posteriors, novelty_threshold):
    """
    Determine final classification based on posterior probabilities

    Returns:
    - classification: Best candidate with confidence score
    - is_novel: Whether classification is potentially novel (low confidence)
    """
    if not candidates or not posteriors:
        return {
            'method': 'EM_probabilistic',
            'classification': 'Unclassified',
            'confidence': 0.0,
            'is_novel': True,
            'reason': 'No candidate taxa identified'
        }, True

    # Find candidate with highest posterior probability
    best_idx = max(posteriors.items(), key=lambda x: x[1])[0]
    best_candidate = candidates[best_idx]
    best_posterior = posteriors[best_idx]

    # Determine confidence level
    is_novel = best_posterior < novelty_threshold

    if best_posterior >= 0.9:
        confidence_level = 'high'
    elif best_posterior >= 0.7:
        confidence_level = 'medium'
    elif best_posterior >= novelty_threshold:
        confidence_level = 'low'
    else:
        confidence_level = 'very_low_novel'

    classification = {
        'method': 'EM_probabilistic',
        'taxid': best_candidate.get('taxid'),
        'name': best_candidate.get('name'),
        'reference': best_candidate.get('reference'),
        'confidence': best_posterior,
        'confidence_level': confidence_level,
        'is_novel': is_novel,
        'source': best_candidate.get('all_sources', best_candidate.get('source')),
        'num_sources': best_candidate.get('num_sources', 1),
        'identity': best_candidate.get('identity'),
        'ani': best_candidate.get('ani'),
        'likelihood': best_candidate.get('merged_likelihood', best_candidate.get('likelihood'))
    }

    return classification, is_novel


def write_outputs(output_prefix, results, all_candidates, posteriors):
    """Write classification results to output files"""
    # CSV output - single best classification
    write_csv(f'{output_prefix}_classification.csv', results)

    # JSON output - complete results with all candidates
    write_json(f'{output_prefix}_classification.json', results, all_candidates, posteriors)

    # Combined text output - human-readable
    write_combined(f'{output_prefix}_combined.txt', results, all_candidates, posteriors)


def write_csv(filename, results):
    """Write CSV output with single best classification"""
    with open(filename, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow([
            'Sample', 'Cluster', 'Method', 'Classification',
            'Confidence', 'Confidence_Level', 'Is_Novel', 'TaxID', 'Sources'
        ])

        classification = results['classification']

        writer.writerow([
            results['meta']['id'],
            results['meta']['cluster_id'],
            classification.get('method', 'EM_probabilistic'),
            classification.get('name', classification.get('classification', 'Unknown')),
            f"{classification.get('confidence', 0.0):.4f}",
            classification.get('confidence_level', 'unknown'),
            classification.get('is_novel', True),
            classification.get('taxid', ''),
            classification.get('source', '')
        ])


def write_json(filename, results, all_candidates, posteriors):
    """Write comprehensive JSON output"""
    output = {
        'meta': results['meta'],
        'classification': results['classification'],
        'em_algorithm': results['em_stats'],
        'all_candidates': [
            {
                **candidate,
                'posterior_probability': posteriors.get(i, 0.0)
            }
            for i, candidate in enumerate(all_candidates)
        ],
        'num_candidates': len(all_candidates)
    }

    with open(filename, 'w') as f:
        json.dump(output, f, indent=2)


def write_combined(filename, results, all_candidates, posteriors):
    """Write human-readable combined output"""
    with open(filename, 'w') as f:
        f.write(f"Probabilistic Classification Results - EM Algorithm\n")
        f.write(f"Sample: {results['meta']['id']}, Cluster: {results['meta']['cluster_id']}\n")
        f.write("=" * 70 + "\n\n")

        # Best classification
        classification = results['classification']
        f.write("BEST CLASSIFICATION:\n")
        f.write(f"  Taxon: {classification.get('name', 'Unknown')}\n")
        f.write(f"  Confidence: {classification.get('confidence', 0.0):.4f} ({classification.get('confidence_level', 'unknown')})\n")
        f.write(f"  Potentially Novel: {classification.get('is_novel', True)}\n")
        f.write(f"  Sources: {classification.get('source', 'none')}\n")

        if classification.get('taxid'):
            f.write(f"  TaxID: {classification['taxid']}\n")
        if classification.get('identity'):
            f.write(f"  BLAST Identity: {classification['identity']:.1f}%\n")
        if classification.get('ani'):
            f.write(f"  FastANI: {classification['ani']:.1f}%\n")

        f.write("\n")

        # EM statistics
        f.write("EM ALGORITHM STATISTICS:\n")
        em_stats = results['em_stats']
        f.write(f"  Iterations: {em_stats['iterations']}\n")
        f.write(f"  Converged: {em_stats['converged']}\n")
        f.write(f"  Candidate Taxa: {em_stats['num_candidates']}\n")
        f.write("\n")

        # All candidates with posteriors
        if all_candidates:
            f.write("ALL CANDIDATE TAXA (sorted by posterior probability):\n")

            # Sort by posterior probability
            sorted_candidates = sorted(
                [(i, c, posteriors.get(i, 0.0)) for i, c in enumerate(all_candidates)],
                key=lambda x: x[2],
                reverse=True
            )

            for idx, candidate, posterior in sorted_candidates:
                f.write(f"\n  {idx + 1}. {candidate.get('name', 'Unknown')}\n")
                f.write(f"     Posterior P(taxon|consensus): {posterior:.4f}\n")
                f.write(f"     Sources: {candidate.get('all_sources', candidate.get('source'))}\n")

                if candidate.get('identity'):
                    f.write(f"     BLAST Identity: {candidate['identity']:.1f}%\n")
                if candidate.get('ani'):
                    f.write(f"     FastANI: {candidate['ani']:.1f}%\n")


def main():
    args = parse_args()

    # Parse classification results from all sources
    all_candidates = []

    if args.kraken2:
        kraken2_candidates = parse_kraken2(args.kraken2, args.min_kraken2_confidence)
        all_candidates.extend(kraken2_candidates)
        print(f"KRAKEN2: {len(kraken2_candidates)} candidates", file=sys.stderr)

    if args.blast:
        blast_candidates = parse_blast(args.blast, args.min_blast_identity)
        all_candidates.extend(blast_candidates)
        print(f"BLAST: {len(blast_candidates)} candidates", file=sys.stderr)

    if args.fastani:
        fastani_candidates = parse_fastani(args.fastani, args.min_ani_similarity)
        all_candidates.extend(fastani_candidates)
        print(f"FastANI: {len(fastani_candidates)} candidates", file=sys.stderr)

    # Merge candidates from multiple sources
    merged_candidates = merge_candidates(all_candidates)
    print(f"Merged: {len(merged_candidates)} unique taxa", file=sys.stderr)

    # Run EM algorithm
    posteriors, iterations, converged = run_em_algorithm(
        merged_candidates,
        args.max_em_iterations,
        args.em_convergence_threshold
    )

    # Determine final classification
    classification, is_novel = determine_classification(
        merged_candidates,
        posteriors,
        args.novelty_threshold
    )

    # Build results structure
    results = {
        'meta': {
            'id': args.sample_id,
            'cluster_id': args.cluster_id
        },
        'classification': classification,
        'em_stats': {
            'iterations': iterations,
            'converged': converged,
            'num_candidates': len(merged_candidates)
        }
    }

    # Write outputs
    write_outputs(args.output_prefix, results, merged_candidates, posteriors)

    # Print summary
    print(f"\nClassification complete:", file=sys.stderr)
    print(f"  Best match: {classification.get('name', 'Unknown')}", file=sys.stderr)
    print(f"  Confidence: {classification.get('confidence', 0.0):.4f} ({classification.get('confidence_level', 'unknown')})", file=sys.stderr)
    print(f"  Potentially novel: {is_novel}", file=sys.stderr)
    print(f"  EM iterations: {iterations} (converged: {converged})", file=sys.stderr)


if __name__ == '__main__':
    main()
