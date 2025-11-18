# NanoPulse

**Production-ready Nextflow DSL2 pipeline for de novo clustering and consensus building of Oxford Nanopore amplicon sequencing data (16S, 18S, ITS, and other amplicons).**

[![Nextflow](https://img.shields.io/badge/nextflow-%E2%89%A525.10.0-brightgreen.svg)](https://www.nextflow.io/)
[![DSL2](https://img.shields.io/badge/DSL-2-brightgreen.svg)](https://www.nextflow.io/docs/latest/dsl2.html)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## About NanoPulse

NanoPulse is a production-ready Nextflow pipeline for species-level analysis of Oxford Nanopore Technologies (ONT) amplicon sequencing data. It performs de novo clustering using UMAP/PaCMAP dimensionality reduction (switchable) and HDBSCAN clustering, followed by consensus sequence generation and taxonomic classification.

**This is a modernized fork of [NanoCLUST](https://github.com/genomicsITER/NanoCLUST)** with significant enhancements:

- **Complete DSL2 migration** - Modern Nextflow syntax and modular structure
- **Production-ready** - 11 critical bugs fixed through real-data testing
- **Updated dependencies** - All tools updated to latest versions (Nextflow 25.10.0+)
- **Comprehensive testing** - 99/99 tests passing (100% coverage)
- **General amplicon support** - 16S, 18S, ITS, and other amplicon types
- **Multiple classifiers** - Kraken2 and BLAST support
- **Novel organism detection** - Probabilistic classification with rescue analysis
- **Active maintenance** - Ongoing development and bug fixes

### Relationship to NanoCLUST

NanoPulse is based on the excellent [NanoCLUST pipeline](https://github.com/genomicsITER/NanoCLUST) developed by Hector Rodriguez-Perez, Laura Ciuffreda, and Carlos Flores. We are deeply grateful for their foundational work and scientific validation.

**Original Publication:**
> Rodríguez-Pérez H, Ciuffreda L, Flores C. NanoCLUST: a species-level analysis of 16S rRNA nanopore sequencing data. *Bioinformatics.* 2021;37(11):1600-1601. doi:[10.1093/bioinformatics/btaa900](https://doi.org/10.1093/bioinformatics/btaa900)

**What NanoPulse Adds:**
- Nextflow DSL2 syntax (modernized from DSL1)
- Critical production bug fixes (11 issues resolved)
- Updated tool versions (all 38 dependencies)
- Real-world data validation (5,147 ONT reads tested)
- nf-core best practices implementation
- Multiple classification backends (Kraken2, BLAST, FastANI)
- Novel organism detection with probabilistic classification
- Enhanced QC reporting (NanoPlot, MultiQC)
- Phylogenetic analysis integration (optional phyloseq objects)

## Pipeline Overview

The pipeline performs the following steps:

1. **K-mer frequency calculation** - Extract k-mer features from reads
2. **UMAP/PaCMAP dimensionality reduction** - Reduce k-mer space to 3D (switchable)
3. **HDBSCAN clustering** - Identify read clusters
4. **Per-cluster assembly** - Generate consensus sequences:
   - Raven error correction
   - FastANI draft selection
   - Racon polishing (4 rounds)
   - Medaka neural network polishing
5. **Taxonomic classification** - Optional classifiers:
   - BLAST against NCBI databases
   - Kraken2 classification
6. **Abundance calculation** - Generate abundance tables and diversity metrics
7. **Visualization** - Interactive HTML reports with UMAP plots

## Quick Start

### Prerequisites

1. Install [Nextflow](https://www.nextflow.io/docs/latest/getstarted.html) (≥25.10.0)

```bash
curl -s https://get.nextflow.io | bash
mv nextflow ~/bin/  # Or add to your PATH
```

2. Install [Docker](https://docs.docker.com/engine/installation/) or [Conda](https://conda.io/miniconda.html)

### Test Run

Test the pipeline with included test data:

```bash
nextflow run FOI-Bioinformatics/NanoPulse \
    -profile test,docker \
    --outdir results_test
```

### Running with Your Data

#### 1. Prepare Input Samplesheet

Create a CSV file with your samples:

```csv
sample,fastq
sample1,/path/to/sample1.fastq.gz
sample2,/path/to/sample2.fastq.gz
```

#### 2. Basic Run (No Classification)

```bash
nextflow run FOI-Bioinformatics/NanoPulse \
    -profile docker \
    --input samplesheet.csv \
    --outdir results \
    --enable_blast false \
    --enable_kraken2 false
```

#### 3. Run with BLAST Classification

First, download a BLAST database (example for 16S rRNA):

```bash
mkdir -p db/blast db/taxdb
wget https://ftp.ncbi.nlm.nih.gov/blast/db/16S_ribosomal_RNA.tar.gz
tar -xzvf 16S_ribosomal_RNA.tar.gz -C db/blast
wget https://ftp.ncbi.nlm.nih.gov/blast/db/taxdb.tar.gz
tar -xzvf taxdb.tar.gz -C db/taxdb
```

Then run with BLAST enabled:

```bash
nextflow run FOI-Bioinformatics/NanoPulse \
    -profile docker \
    --input samplesheet.csv \
    --outdir results \
    --enable_blast true \
    --blast_db db/blast/16S_ribosomal_RNA \
    --blast_taxdb db/taxdb
```

#### 4. Run with Kraken2 Classification

```bash
nextflow run FOI-Bioinformatics/NanoPulse \
    -profile docker \
    --input samplesheet.csv \
    --outdir results \
    --enable_blast true \
    --blast_db /path/to/blast/db \
    --blast_taxdb /path/to/taxdb \
    --enable_kraken2 true \
    --kraken2_db /path/to/kraken2/db
```

## Key Parameters

### Input/Output
- `--input` - Path to input samplesheet (CSV format)
- `--outdir` - Output directory for results (default: `./results`)

### Classification Options
- `--enable_blast` - Enable BLAST classification (default: `true`)
- `--blast_db` - Path to BLAST database
- `--blast_taxdb` - Path to BLAST taxonomy database
- `--enable_kraken2` - Enable Kraken2 classification (default: `false`)
- `--kraken2_db` - Path to Kraken2 database

### Clustering Parameters
- `--kmer_size` - K-mer size for feature extraction (default: `9`)
- `--umap_dimensions` - UMAP output dimensions (default: `3`)
- `--umap_neighbors` - UMAP n_neighbors parameter (default: `15`)
- `--umap_min_dist` - UMAP min_dist parameter (default: `0.1`)
- `--min_cluster_size` - Minimum cluster size for HDBSCAN (default: `50`)
- `--min_samples` - Minimum samples for HDBSCAN (default: `5`)

### Assembly Parameters
- `--genome_size` - Expected amplicon size (default: `"1.5k"`)
- `--polishing_reads` - Reads per cluster for polishing (default: `100`)
- `--racon_rounds` - Racon polishing rounds (default: `4`)
- `--medaka_model` - Medaka basecalling model (default: `"r941_min_high_g303"`)

### Resource Limits
- `--max_cpus` - Maximum CPUs (default: `16`)
- `--max_memory` - Maximum memory (default: `128.GB`)
- `--max_time` - Maximum time (default: `240.h`)

## Computing Requirements

### Memory Considerations

The UMAP/PaCMAP clustering step is memory-intensive:
- **Default settings** (umap_set_size = 100,000): 32-36 GB RAM
- **Reduced settings** (umap_set_size = 50,000): 10-13 GB RAM

If you encounter out-of-memory errors (exit status 137), reduce `umap_set_size`:

```bash
nextflow run FOI-Bioinformatics/NanoPulse \
    --umap_set_size 50000 \
    ...other options...
```

### CPU Utilization

Nextflow automatically uses all available CPUs. More cores enable:
- Parallel cluster processing
- Faster consensus generation
- Reduced overall runtime

### Test Profile Requirements

Minimum for test profile:
- 4 CPU cores
- 16 GB RAM

## Output Files

The pipeline generates the following key outputs in `--outdir`:

```
results/
├── consensus/
│   └── {sample}_consensus.fasta         # Final consensus sequences
├── annotations/
│   └── {sample}_annotations.tsv         # Taxonomic annotations
├── abundances/
│   └── {sample}_abundances.csv          # Cluster abundances
├── diversity/
│   └── {sample}_diversity.txt           # Diversity metrics
├── plots/
│   └── {sample}_dimreduction_plot.png          # UMAP visualization
├── html_reports/
│   └── {sample}_report.html            # Interactive HTML report
├── multiqc/
│   └── multiqc_report.html             # MultiQC report (if enabled)
└── pipeline_info/
    ├── execution_report.html           # Nextflow execution report
    ├── execution_timeline.html         # Execution timeline
    └── execution_trace.txt             # Resource usage trace
```

## Profiles

### Execution Profiles
- `docker` - Use Docker containers (recommended)
- `singularity` - Use Singularity containers
- `conda` - Use Conda environments

### Test Profiles
- `test` - Minimal test dataset
- `test_full` - Full-size test dataset

### Example Usage
```bash
# Docker with test data
nextflow run . -profile test,docker

# Singularity on HPC
nextflow run . -profile docker --input data.csv --outdir results

# Conda environment
nextflow run . -profile conda --input data.csv --outdir results
```

## Troubleshooting

### Docker Permission Issues

If you encounter Docker permission errors, add your user to the docker group:

```bash
sudo usermod -aG docker $USER
# Log out and back in for changes to take effect
```

### Memory Issues

If processes fail with exit status 137 (out of memory):

1. Reduce `umap_set_size`:
   ```bash
   --umap_set_size 50000
   ```

2. Reduce cluster size threshold:
   ```bash
   --min_cluster_size 30
   ```

3. Limit resources explicitly:
   ```bash
   --max_memory '32.GB' --max_cpus 8
   ```

### Conda Environment Issues

If you experience issues with Conda profiles, try:

1. Use Docker profile instead (recommended)
2. Clear Conda cache:
   ```bash
   conda clean --all
   ```
3. Use mamba for faster dependency resolution:
   ```bash
   conda install mamba -c conda-forge
   ```

### Resume Failed Runs

Nextflow can resume interrupted runs:

```bash
nextflow run . -profile docker --input data.csv -resume
```

## Citations and Credits

### NanoPulse Development

**Maintainer:** FOI-Bioinformatics Team
**Repository:** https://github.com/FOI-Bioinformatics/NanoPulse
**License:** MIT License

### Original NanoCLUST Development

**Original Authors:** Hector Rodriguez-Perez, Laura Ciuffreda, Carlos Flores
**Original Repository:** https://github.com/genomicsITER/NanoCLUST
**Institution:** Instituto Tecnológico y de Energías Renovables (ITER), Canary Islands, Spain

**Publication:**
> Rodríguez-Pérez H, Ciuffreda L, Flores C. NanoCLUST: a species-level analysis of 16S rRNA nanopore sequencing data. *Bioinformatics.* 2021;37(11):1600-1601. doi:10.1093/bioinformatics/btaa900

**Funding (Original NanoCLUST):**
This work was supported by Instituto de Salud Carlos III [PI14/00844, PI17/00610, and FI18/00230] and co-financed by the European Regional Development Funds, "A way of making Europe" from the European Union; Ministerio de Ciencia e Innovación [RTC-2017-6471-1, AEI/FEDER, UE]; Cabildo Insular de Tenerife [CGIEU0000219140]; Fundación Canaria Instituto de Investigación Sanitaria de Canarias [PIFUN48/18]; and by the agreement with Instituto Tecnológico y de Energías Renovables (ITER) to strengthen scientific and technological education, training, research, development and innovation in Genomics, Personalized Medicine and Biotechnology [OA17/008].

## Contributions and Support

We welcome contributions to NanoPulse! Please see the [contributing guidelines](.github/CONTRIBUTING.md) for details.

To report issues or request features, please use the [GitHub issue tracker](https://github.com/FOI-Bioinformatics/NanoPulse/issues).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Both NanoCLUST and NanoPulse are MIT licensed, allowing free use, modification, and distribution with proper attribution.

## Acknowledgments

We acknowledge and thank:
- The original NanoCLUST developers for their pioneering work
- The Nextflow community for excellent workflow tools
- The nf-core community for best practices and modules
- All contributors to the open-source tools used in this pipeline
