#!/usr/bin/env python3

import sys
from Bio import SeqIO
from Bio.SeqIO.QualityIO import FastqGeneralIterator
from Bio.SeqIO.FastaIO import SimpleFastaParser
from collections import Counter,OrderedDict
from itertools import product,groupby
import math
import multiprocessing
import pandas as pd
from tqdm import tqdm
import argparse

def parse_args():
    parser = argparse.ArgumentParser(description='Calculate k-mer frequencies for reads')

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

    return parser.parse_args()

def launch_pool(procs, funct, args):
    p = multiprocessing.Pool(processes=procs)
    try:
        results = p.map(funct, args)
        p.close()
        p.join()
    except KeyboardInterrupt:
        p.terminate()
    return results

def chunks(l, n):
    """Yield successive n-sized chunks from l."""
    for i in range(0, len(l), n):
        yield l[i:i+n]

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
    read_id, seq, k, combined_kmers, count, frac = args_tuple

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
    return (read_id, [freqs.get(k, 0) for k in combined_kmers])

def build_args_for_kmer_calc(read_num, target_range, args_list, read_id, seq, k, combined_kmers, lengths_d, count, frac):
    """Build arguments for k-mer calculation."""
    status = "keep going"
    if read_num >= target_range[0] and read_num <= target_range[1]:
        lengths_d[read_id] = len(seq)
        args_list.append((read_id, seq.upper(), k, combined_kmers, count, frac))
    elif read_num > target_range[1]:
        status = "over"
    return args_list, status

def launch_seq_kmers_pool(fastx, ftype, k, threads, target_range, combined_kmers, count, frac):
    """Launch parallel k-mer calculation."""
    args = []
    lengths_d = {}

    if ftype == "fastq":
        for read_num, (read_id, seq, qual) in enumerate(FastqGeneralIterator(open(fastx))):
            args, status = build_args_for_kmer_calc(read_num, target_range, args, read_id, seq, k, combined_kmers, lengths_d, count, frac)
            if status == "over":
                break
    elif ftype == "fasta":
        for read_num, (read_id, seq) in enumerate(SimpleFastaParser(open(fastx))):
            args, status = build_args_for_kmer_calc(read_num, target_range, args, read_id, seq, k, combined_kmers, lengths_d, count, frac)
            if status == "over":
                break

    results = launch_pool(threads, calc_seq_kmer_freqs, args)
    return dict(results), lengths_d

def print_comp_vectors(read_num, target_range, comp_vectors, read_id, lengths_d):
    """Print k-mer frequency vectors."""
    status = "keep going"
    if read_num >= target_range[0] and read_num <= target_range[1]:
        comp_vec_str = "\t".join(map(lambda x: str(round(x, 4)), comp_vectors[read_id]))
        print(f"{read_id.split()[0]}\t{lengths_d[read_id]}\t{comp_vec_str}")
    elif read_num > target_range[1]:
        status = "over"
    return status

def write_output(fastx, ftype, comp_vectors, lengths_d, target_range):
    """Write k-mer frequency output."""
    if ftype == "fastq":
        for read_num, (read_id, seq, qual) in enumerate(FastqGeneralIterator(open(fastx))):
            status = print_comp_vectors(read_num, target_range, comp_vectors, read_id, lengths_d)
            if status == "over":
                break
    elif ftype == "fasta":
        for read_num, (read_id, seq) in enumerate(SimpleFastaParser(open(fastx))):
            status = print_comp_vectors(read_num, target_range, comp_vectors, read_id, lengths_d)
            if status == "over":
                break

def get_n_reads(fastx, ftype):
    """Count number of reads in file."""
    if ftype == "fastq":
        n_reads = sum(1 for _ in FastqGeneralIterator(open(fastx)))
    elif ftype == "fasta":
        n_reads = sum(1 for _ in SimpleFastaParser(open(fastx)))
    return n_reads

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

def main(args):
    # Determine file type
    ftype = check_input_format(args.reads)
    n_reads = get_n_reads(args.reads, ftype)

    # Process in chunks for memory efficiency
    chunk_n_reads = 5000

    # Build k-mer dictionary
    all_kmers = build_all_kmers(args.kmer_size)
    combined_kmers = combine_kmers_list(all_kmers)

    # Print header
    print(f"read\tlength\t{chr(9).join(combined_kmers)}")

    # Process reads in chunks
    read_chunks = list(chunks(range(n_reads), chunk_n_reads))

    for chunk in tqdm(read_chunks, desc="Processing reads"):
        target_range = (chunk[0], chunk[-1])

        comp_vectors, lengths_d = launch_seq_kmers_pool(
            args.reads,
            ftype,
            args.kmer_size,
            args.threads,
            target_range,
            combined_kmers,
            args.count,
            args.frac
        )

        write_output(args.reads, ftype, comp_vectors, lengths_d, target_range)

if __name__ == "__main__":
    args = parse_args()
    main(args)
