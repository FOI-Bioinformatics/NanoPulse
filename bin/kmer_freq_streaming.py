#!/usr/bin/env python3

import sys
from Bio.SeqIO.QualityIO import FastqGeneralIterator
from Bio.SeqIO.FastaIO import SimpleFastaParser
from collections import Counter, OrderedDict
from itertools import product
import multiprocessing
from tqdm import tqdm
import argparse
import numpy as np
from scipy.sparse import csr_matrix, save_npz

def parse_args():
    parser = argparse.ArgumentParser(description='Calculate k-mer frequencies for reads - optimized streaming version')

    # Mandatory arguments
    parser.add_argument('-r', '--reads', required=True,
                       help='Fasta/fastq file containing read sequences', type=str)

    # Optional arguments
    parser.add_argument('-k', '--kmer-size', help='k-mer size [7]', type=int, default=7)
    parser.add_argument('-t', '--threads', help='Number of threads [4]', type=int, default=4)
    parser.add_argument('-c', '--count', help='Provide raw k-mer counts, not normalized',
                       action='store_true', default=False)
    parser.add_argument('-f', '--frac', help='Normalize k-mer counts by total number',
                       action='store_true', default=False)
    parser.add_argument('--output-format', help='Output format: tsv, npz (sparse), or both [both]',
                       type=str, default='both', choices=['tsv', 'npz', 'both'])
    parser.add_argument('--output-prefix', help='Output file prefix (for npz format) [kmer_freqs]',
                       type=str, default='kmer_freqs')

    return parser.parse_args()

def launch_pool(procs, funct, args):
    """Execute parallel processing with multiprocessing pool."""
    p = multiprocessing.Pool(processes=procs)
    try:
        results = p.map(funct, args)
        p.close()
        p.join()
    except KeyboardInterrupt:
        p.terminate()
    return results

def rev_comp_motif(motif):
    """Return reverse complement of DNA sequence."""
    complement = {'A': 'T', 'C': 'G', 'G': 'C', 'T': 'A'}
    return ''.join([complement.get(base, base) for base in motif[::-1]])

def build_all_kmers(k):
    """Generate all possible k-mers of length k."""
    bases = ['A', 'C', 'G', 'T']
    return [''.join(p) for p in product(bases, repeat=k)]

def combine_kmers_list(all_kmers):
    """Combine k-mers with their reverse complements."""
    combined = OrderedDict()
    for kmer in all_kmers:
        rc = rev_comp_motif(kmer)
        if kmer not in combined and rc not in combined:
            combined[kmer] = None
    return list(combined.keys())

def calc_seq_kmer_freqs(args_tuple):
    """Calculate k-mer frequencies for a single sequence."""
    read_id, seq, length, k, combined_kmers, count, frac = args_tuple

    # Count k-mers in sequence
    kmer_counts = Counter()
    for i in range(len(seq) - k + 1):
        kmer = seq[i:i+k]
        kmer_counts[kmer] += 1

    # Combine with reverse complements
    combined_counts = {}
    for kmer in combined_kmers:
        rc = rev_comp_motif(kmer)
        combined_counts[kmer] = kmer_counts.get(kmer, 0) + kmer_counts.get(rc, 0)

    # Normalize if requested
    total = sum(combined_counts.values())
    if not count and not frac and total > 0:
        freqs = {k: v/total for k, v in combined_counts.items()}
    elif frac and total > 0:
        freqs = {k: v/total for k, v in combined_counts.items()}
    else:
        freqs = combined_counts

    # Return as ordered vector
    return (read_id, length, [freqs.get(k, 0) for k in combined_kmers])

def check_input_format(fastx):
    """Determine if input is FASTA or FASTQ."""
    with open(fastx) as f:
        first_char = f.read(1)

    if first_char == "@":
        return "fastq"
    elif first_char == ">":
        return "fasta"
    else:
        raise ValueError("Unexpected file type! Only FASTA/FASTQ recognized.")

def process_sequences_streaming(fastx, ftype, k, threads, combined_kmers, count, frac, output_format='tsv', chunk_size=5000):
    """
    Process sequences in a single pass with streaming architecture.

    Key optimization: Read file once, process in chunks, output immediately.
    No file re-opening, no redundant read counting.

    Args:
        output_format: 'tsv' for TSV output only, 'npz' to collect for sparse matrix, 'both' for both

    Returns:
        all_results: List of (read_id, length, freqs) if collecting for sparse output, else None
    """
    # Select appropriate parser
    if ftype == "fastq":
        parser = FastqGeneralIterator(open(fastx))
    else:
        parser = SimpleFastaParser(open(fastx))

    # Process sequences in chunks
    args_batch = []
    n_processed = 0
    all_results = [] if output_format in ['npz', 'both'] else None

    # Use tqdm for progress tracking without knowing total (streaming)
    with tqdm(desc="Processing reads", unit=" reads") as pbar:
        for record in parser:
            if ftype == "fastq":
                read_id, seq, qual = record
            else:
                read_id, seq = record

            # Build arguments for parallel processing
            length = len(seq)
            args_batch.append((read_id, seq.upper(), length, k, combined_kmers, count, frac))
            n_processed += 1

            # Process chunk when it reaches chunk_size
            if len(args_batch) >= chunk_size:
                results = launch_pool(threads, calc_seq_kmer_freqs, args_batch)

                # Output TSV if requested
                if output_format in ['tsv', 'both']:
                    for read_id, length, freqs in results:
                        freqs_str = "\t".join(map(lambda x: str(round(x, 4)), freqs))
                        print(f"{read_id.split()[0]}\t{length}\t{freqs_str}")

                # Collect results for sparse matrix if requested
                if output_format in ['npz', 'both']:
                    all_results.extend(results)

                # Clear batch and update progress
                args_batch = []
                pbar.update(chunk_size)

        # Process remaining reads
        if args_batch:
            results = launch_pool(threads, calc_seq_kmer_freqs, args_batch)

            if output_format in ['tsv', 'both']:
                for read_id, length, freqs in results:
                    freqs_str = "\t".join(map(lambda x: str(round(x, 4)), freqs))
                    print(f"{read_id.split()[0]}\t{length}\t{freqs_str}")

            if output_format in ['npz', 'both']:
                all_results.extend(results)

            pbar.update(len(args_batch))

    return all_results

def save_sparse_matrix(results, combined_kmers, output_prefix):
    """
    Save k-mer frequency data as sparse matrix in NPZ format.

    Sparse matrices provide ~90% memory reduction for k-mer data which is typically
    very sparse (most k-mers have zero frequency in any given read).

    Args:
        results: List of (read_id, length, freqs) tuples
        combined_kmers: List of k-mer names (column headers)
        output_prefix: Output file prefix (will add .npz extension)
    """
    print(f"\nConverting to sparse matrix format...", file=sys.stderr)

    # Extract data components
    read_ids = [r[0].split()[0] for r in results]
    lengths = [r[1] for r in results]
    freq_matrix = np.array([r[2] for r in results], dtype=np.float32)

    # Convert to sparse matrix (CSR format is optimal for row-slicing)
    # CSR (Compressed Sparse Row) is ideal for:
    # - Row-wise operations (common in clustering)
    # - Memory efficiency (stores only non-zero values)
    sparse_matrix = csr_matrix(freq_matrix)

    # Calculate sparsity
    n_elements = freq_matrix.shape[0] * freq_matrix.shape[1]
    n_nonzero = np.count_nonzero(freq_matrix)
    sparsity = 100 * (1 - n_nonzero / n_elements)

    print(f"Matrix shape: {freq_matrix.shape}", file=sys.stderr)
    print(f"Sparsity: {sparsity:.2f}% (storing only {n_nonzero:,} of {n_elements:,} values)", file=sys.stderr)
    print(f"Memory reduction: ~{sparsity:.1f}%", file=sys.stderr)

    # Save sparse matrix and metadata
    save_npz(f"{output_prefix}.npz", sparse_matrix)

    # Save metadata separately (read IDs and lengths)
    np.savez(
        f"{output_prefix}_metadata.npz",
        read_ids=np.array(read_ids, dtype=object),
        lengths=np.array(lengths, dtype=np.int32),
        kmer_names=np.array(combined_kmers, dtype=object)
    )

    print(f"Sparse matrix saved to {output_prefix}.npz", file=sys.stderr)
    print(f"Metadata saved to {output_prefix}_metadata.npz", file=sys.stderr)

def main(args):
    # Determine file type (single file open)
    ftype = check_input_format(args.reads)

    # Build k-mer dictionary
    all_kmers = build_all_kmers(args.kmer_size)
    combined_kmers = combine_kmers_list(all_kmers)

    # Print header if TSV output is requested
    if args.output_format in ['tsv', 'both']:
        print(f"read\tlength\t{chr(9).join(combined_kmers)}")

    # Process sequences in streaming mode (single pass, no re-opening)
    results = process_sequences_streaming(
        args.reads,
        ftype,
        args.kmer_size,
        args.threads,
        combined_kmers,
        args.count,
        args.frac,
        args.output_format
    )

    # Save sparse matrix if requested
    if args.output_format in ['npz', 'both'] and results:
        save_sparse_matrix(results, combined_kmers, args.output_prefix)

if __name__ == "__main__":
    args = parse_args()
    main(args)
