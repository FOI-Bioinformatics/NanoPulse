# Database Setup Guide for NanoPulse

This guide explains how to set up classification databases for use with NanoPulse.

## Overview

NanoPulse supports two classification backends for amplicon sequences:
- **BLAST** - Sequence alignment-based classification (recommended for amplicons)
- **Kraken2** - K-mer based classification (fast, but less accurate for short amplicons)

**Important**: FastANI is designed for whole-genome comparisons and is **not appropriate for amplicon sequences** (16S, 18S, ITS). For amplicon analysis, use BLAST with curated databases like SILVA, RDP, or UNITE.

Both classification backends are optional and can be enabled/disabled via parameters.

## Quick Start

### Option 1: Pre-built Databases (Recommended for 16S/18S)

For standard 16S/18S amplicon analysis, use SILVA databases:

```bash
# Download and prepare SILVA 138 for BLAST
wget https://www.arb-silva.de/fileadmin/silva_databases/release_138/Exports/SILVA_138_SSURef_NR99_tax_silva.fasta.gz
gunzip SILVA_138_SSURef_NR99_tax_silva.fasta.gz

# Create BLAST database
makeblastdb -in SILVA_138_SSURef_NR99_tax_silva.fasta \
  -dbtype nucl \
  -out databases/silva138/silva138 \
  -parse_seqids \
  -hash_index

# Run NanoPulse with BLAST
nextflow run FOI-Bioinformatics/NanoPulse \
  --input samplesheet.csv \
  --enable_blast true \
  --blast_db databases/silva138/silva138 \
  --outdir results
```

### Option 2: Automated Download (Coming Soon - Phase 14)

Phase 14 will add automated database download and setup:

```bash
# Download SILVA databases automatically
nextflow run FOI-Bioinformatics/NanoPulse \
  --setup_databases true \
  --database_type silva \
  --database_dir databases/
```

## Manual Database Setup

### BLAST Database

**For 16S rRNA:**

```bash
# SILVA (recommended for environmental samples)
wget https://www.arb-silva.de/fileadmin/silva_databases/release_138/Exports/SILVA_138_SSURef_NR99_tax_silva.fasta.gz
gunzip SILVA_138_SSURef_NR99_tax_silva.fasta.gz
makeblastdb -in SILVA_138_SSURef_NR99_tax_silva.fasta -dbtype nucl -out silva138

# RDP (alternative)
wget https://rdp.cme.msu.edu/download/current_Bacteria_unaligned.fa.gz
gunzip current_Bacteria_unaligned.fa.gz
makeblastdb -in current_Bacteria_unaligned.fa -dbtype nucl -out rdp_bacteria
```

**For ITS (fungi):**

```bash
# UNITE
wget https://files.plutof.ut.ee/public/orig/6C/96/6C96A3C5E3B4C8A67D60F7DB56AA2DC9A28E17BA1F1DAE0D89F551D0C0B75E76.gz
gunzip 6C96A3C5E3B4C8A67D60F7DB56AA2DC9A28E17BA1F1DAE0D89F551D0C0B75E76.gz
makeblastdb -in sh_general_release_*.fasta -dbtype nucl -out unite_its
```

**NCBI Taxonomy Database (optional but recommended):**

```bash
# Download NCBI taxonomy
wget ftp://ftp.ncbi.nlm.nih.gov/blast/db/taxdb.tar.gz
tar -xzf taxdb.tar.gz -C databases/ncbi_taxonomy/
```

### Kraken2 Database

```bash
# Standard Kraken2 database (requires ~100GB disk space)
kraken2-build --standard --threads 8 --db databases/kraken2_standard

# Or download pre-built
wget https://genome-idx.s.3.amazonaws.com/kraken/k2_standard_20220607.tar.gz
mkdir -p databases/kraken2_standard
tar -xzf k2_standard_20220607.tar.gz -C databases/kraken2_standard

# Custom database for specific taxa
kraken2-build --download-taxonomy --db databases/kraken2_custom
kraken2-build --download-library bacteria --db databases/kraken2_custom
kraken2-build --download-library archaea --db databases/kraken2_custom
kraken2-build --build --threads 8 --db databases/kraken2_custom
```

### Why No FastANI for Amplicons?

**FastANI is not included** because:
1. It's designed for whole-genome Average Nucleotide Identity calculations
2. Amplicons (16S, 18S, ITS) are too short (typically 300-1,500 bp)
3. FastANI requires genomes to be >80% similar over substantial length
4. BLAST provides superior accuracy for short, conserved amplicon sequences

For amplicon analysis, use **BLAST with curated reference databases** (SILVA, RDP, UNITE).

## Running NanoPulse with Databases

### BLAST Only (Recommended for Amplicons)

```bash
nextflow run FOI-Bioinformatics/NanoPulse \
  --input samplesheet.csv \
  --enable_blast true \
  --blast_db databases/silva138/silva138 \
  --enable_kraken2 false \
  --outdir results
```

### BLAST + Kraken2 (Fast + Accurate)

```bash
nextflow run FOI-Bioinformatics/NanoPulse \
  --input samplesheet.csv \
  --enable_blast true \
  --blast_db databases/silva138/silva138 \
  --blast_taxdb databases/ncbi_taxonomy \
  --enable_kraken2 true \
  --kraken2_db databases/kraken2_standard \
  --outdir results
```

### No Classification (Clustering Only)

```bash
nextflow run FOI-Bioinformatics/NanoPulse \
  --input samplesheet.csv \
  --enable_blast false \
  --enable_kraken2 false \
  --outdir results
```

## Database Recommendations by Amplicon Type

| Amplicon | Recommended Database | Alternative | Size | Download Time |
|----------|---------------------|-------------|------|---------------|
| 16S rRNA | SILVA 138 | RDP | ~400 MB | 5-10 min |
| 18S rRNA | SILVA 138 | PR2 | ~400 MB | 5-10 min |
| ITS | UNITE | - | ~100 MB | 2-5 min |
| Custom | Custom BLAST DB | - | Varies | Varies |

## Troubleshooting

### BLAST Database Not Found

```
ERROR: Cannot find BLAST database at: databases/silva138/silva138
```

**Solution:** Ensure all database files exist:
- `silva138.nhr`
- `silva138.nin`
- `silva138.nsq`

Re-run `makeblastdb` if any are missing.

### Kraken2 Database Incomplete

```
ERROR: Kraken2 database is incomplete
```

**Solution:** Kraken2 databases must contain:
- `hash.k2d`
- `opts.k2d`
- `taxo.k2d`


## Phase 14: Automated Database Management (Planned)

The upcoming Phase 14 will add:

1. **Automated downloads** for common databases (SILVA, UNITE, RDP)
2. **Database validation** before pipeline execution
3. **Update mechanism** for keeping databases current
4. **Pre-built containers** with common databases included

Stay tuned for these enhancements!

## References

- **SILVA**: https://www.arb-silva.de/
- **RDP**: https://rdp.cme.msu.edu/
- **UNITE**: https://unite.ut.ee/
- **Kraken2**: https://github.com/DerrickWood/kraken2
- **BLAST**: https://blast.ncbi.nlm.nih.gov/
