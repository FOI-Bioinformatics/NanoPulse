#!/usr/bin/env python3
"""
Generate synthetic ONT FASTQ files for integration testing
Creates realistic-looking nanopore reads with varying characteristics
"""

import random
import argparse
from pathlib import Path


def generate_ont_read_id(read_number: int, channel: int = 42) -> str:
    """Generate realistic ONT read ID"""
    # Format: <instrument>_<run_id>_<flowcell_id>_<channel>_<read_number>
    instruments = ['MN12345', 'PM67890', 'MN54321']
    instrument = random.choice(instruments)
    run_id = f"{random.randint(0, 9999):04d}"
    flowcell = f"FAK{random.randint(10000, 99999)}"

    return f"@{instrument}_{run_id}_{flowcell}_{channel}_{read_number}"


def generate_amplicon_sequence(base_sequence: str, length: int, error_rate: float = 0.02) -> str:
    """
    Generate amplicon sequence from base with errors

    Args:
        base_sequence: Template sequence to base amplicon on
        length: Desired length (will add variation)
        error_rate: Rate of sequencing errors (substitutions, indels)

    Returns:
        Sequence string with realistic errors
    """
    # Repeat/trim base sequence to approximate target length
    repeats = (length // len(base_sequence)) + 1
    sequence = (base_sequence * repeats)[:length]

    # Add length variation (-20% to +20%)
    variation = random.randint(int(-0.2 * length), int(0.2 * length))
    if variation > 0:
        # Add random bases
        sequence += ''.join(random.choices('ACGT', k=variation))
    elif variation < 0:
        # Remove bases
        sequence = sequence[:variation]

    # Introduce errors
    sequence_list = list(sequence)
    num_errors = int(len(sequence_list) * error_rate)

    for _ in range(num_errors):
        pos = random.randint(0, len(sequence_list) - 1)
        error_type = random.choice(['sub', 'ins', 'del'])

        if error_type == 'sub':
            # Substitution
            sequence_list[pos] = random.choice('ACGT')
        elif error_type == 'ins':
            # Insertion
            sequence_list.insert(pos, random.choice('ACGT'))
        elif error_type == 'del' and len(sequence_list) > 100:
            # Deletion
            sequence_list.pop(pos)

    return ''.join(sequence_list)


def generate_quality_scores(length: int, mean_quality: int = 12) -> str:
    """
    Generate Phred+33 quality scores

    Args:
        length: Length of quality string
        mean_quality: Mean Phred quality score

    Returns:
        Quality string in Phred+33 encoding
    """
    qualities = []
    for _ in range(length):
        # Normal distribution around mean_quality with stddev=3
        q = int(random.gauss(mean_quality, 3))
        q = max(3, min(40, q))  # Clamp between 3 and 40
        qualities.append(chr(q + 33))  # Phred+33 encoding

    return ''.join(qualities)


def generate_fastq_record(read_id: str, sequence: str) -> str:
    """Generate complete FASTQ record"""
    quality = generate_quality_scores(len(sequence))
    return f"{read_id}\n{sequence}\n+\n{quality}\n"


def generate_synthetic_dataset(
    output_path: Path,
    num_reads: int,
    amplicon_templates: list,
    amplicon_distribution: list = None,
    avg_length: int = 1500
):
    """
    Generate synthetic ONT amplicon dataset

    Args:
        output_path: Output FASTQ file path
        num_reads: Number of reads to generate
        amplicon_templates: List of template sequences (one per biological cluster)
        amplicon_distribution: List of proportions for each template (must sum to 1.0)
        avg_length: Average read length
    """
    if amplicon_distribution is None:
        # Equal distribution
        amplicon_distribution = [1.0 / len(amplicon_templates)] * len(amplicon_templates)

    assert len(amplicon_templates) == len(amplicon_distribution)
    assert abs(sum(amplicon_distribution) - 1.0) < 0.001, "Distribution must sum to 1.0"

    # Calculate reads per amplicon
    reads_per_amplicon = [int(num_reads * prop) for prop in amplicon_distribution]

    # Adjust for rounding errors
    reads_per_amplicon[-1] += num_reads - sum(reads_per_amplicon)

    with open(output_path, 'w') as fout:
        read_number = 0

        for template_idx, (template, num_template_reads) in enumerate(
            zip(amplicon_templates, reads_per_amplicon)
        ):
            for _ in range(num_template_reads):
                read_id = generate_ont_read_id(read_number)

                # Generate sequence with variation
                length_variation = random.randint(-200, 200)
                target_length = avg_length + length_variation

                sequence = generate_amplicon_sequence(
                    template,
                    target_length,
                    error_rate=0.05  # 5% error rate (realistic for ONT)
                )

                record = generate_fastq_record(read_id, sequence)
                fout.write(record)

                read_number += 1

    print(f"Generated {num_reads} reads -> {output_path}")
    print(f"  Amplicons: {len(amplicon_templates)}")
    print(f"  Distribution: {[f'{p*100:.1f}%' for p in amplicon_distribution]}")


def main():
    parser = argparse.ArgumentParser(description='Generate synthetic ONT FASTQ for testing')
    parser.add_argument('--output', type=Path, required=True, help='Output FASTQ file')
    parser.add_argument('--reads', type=int, required=True, help='Number of reads')
    parser.add_argument('--clusters', type=int, default=3, help='Number of clusters (amplicons)')
    parser.add_argument('--length', type=int, default=1500, help='Average read length')
    parser.add_argument('--seed', type=int, default=42, help='Random seed for reproducibility')

    args = parser.parse_args()

    # Set random seed
    random.seed(args.seed)

    # Create diverse amplicon templates (16S-like sequences)
    # These are realistic 16S rRNA gene fragments with biological variation
    templates = [
        # E. coli-like (V3-V4 region)
        "TACGTAGGTGGCAAGCGTTGTCCGGATTTACTGGGCGTAAAGGGAGCGTAGGCGGACTTTTAAGTGAGAT"
        "GTGAAAGCCCCGGGCTCAACCTGGGAACTGCATTTGGAACTGGCAGACTAGAGTGCGGTAGGGGTAGAG"
        "GGAATTCCCGGTGTAGCGGTGAAATGCGTAGATATCGGGAGGAACACCAGTGGCGAAGGCGCTCTACTG"
        "GGCCATTACTGACGCTGAGGAGCGAAAGCGTGGGGAGCGAACAGGATTAGATACCCTGGTAGTCCACGC",

        # Bacillus-like
        "TACGTAGGTGGCGAGCGTTGTCCGGAATTATTGGGCGTAAAGAGCTCGTAGGCGGCTTGTCACGTCGGA"
        "TGTGAAAGCCCGGGGCTCAACCCGGGATGGGCATTGGAAACTGTCATGCTAGAGTACGGTAGGGGAAGG"
        "GGAATTCCCAGTGTAGCGGTGGAATGCGTAGATATTGGGAAGAACACCAGTGGCGAAGGCGCCTTCCTG"
        "GACAGATACTGACGCTGAGGAGCGAAAGCGTGGGGAGCGAACAGGATTAGATACCCTGGTAGTCCACGC",

        # Pseudomonas-like
        "TACGTAGGGTGCAAGCGTTAATCGGAATTACTGGGCGTAAAGCGCGCGTAGGTGGTTTGTTAAGTTGAA"
        "TGTGAAAGCCCCGGGCTTAACCTGGGAACTGCATCTGATACTGGCAAGCTTGAGTCTCGTAGAGGGGGG"
        "TAGAATTCCAGGTGTAGCGGTGAAATGCGTAGAGATCTGGAGGAATACCGGTGGCGAAGGCGGCCCCCT"
        "GGACAAAGACTGACGCTCAGGTGCGAAAGCGTGGGGAGCAAACAGGATTAGATACCCTGGTAGTCCACG",

        # Staphylococcus-like
        "TACGTATGGTGCAAGCGTTATCCGGAATTATTGGGCGTAAAGAGCTCGTAGGCGGTTTGTCGCGTCTGC"
        "TGTGAAAGTCCGGGGCTCAACCCCGGATCTGCGGTGGGTACGGGCAGACTAGAGTACTGCAGGGGAGAC"
        "TGGAATTCCTGGTGTAGCGGTGGAATGCGCAGATATCAGGAAGAACACCGATGGCGAAGGCAGGTCTCT"
        "GGGCAGTAACTGACGCTGAGGAGCGAAAGCGTGGGTAGCGAACAGGATTAGATACCCTGGTAGTCCATG",

        # Streptococcus-like
        "TACGTATGGAGCAAGCGTTATCCGGATTTATTGGGTTTAAAGGGAGCGTAGATGGATGTTTAAGTCAGT"
        "TGTGAAAGTTTGCGGCTCAACCGTAAAATTGCAGTTGATACTGGATATCTTGAGTGCAGTTGAGGTAGG"
        "CGGAATTCGTGGTGTAGCGGTGAAATGCTTAGATATCACGAAGAACTCCGATTGCGAAGGCAGCTTACT"
        "AAGCTATATCTGACGTTGAAGCGCGAAAGCGTGGGGATCAAACAGGATTAGATACCCTGGTAGTCCACG",
    ]

    # Select subset of templates based on desired cluster count
    selected_templates = templates[:args.clusters]

    # Generate dataset
    generate_synthetic_dataset(
        output_path=args.output,
        num_reads=args.reads,
        amplicon_templates=selected_templates,
        avg_length=args.length
    )


if __name__ == '__main__':
    main()
