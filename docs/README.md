# NanoPulse Documentation

## User Documentation

### Getting Started
- [Introduction](index.md) - Overview of the pipeline
- [Usage](2usage.md) - How to run the pipeline
- [Pipeline Output](3pipeline_output.md) - Understanding your results

### Advanced Features
- [Database Setup](database_setup.md) - Setting up classification databases
- [Phase 11: Novel Organism Detection](PHASE11_USAGE_GUIDE.md) - Using probabilistic classification and rescue analysis

## Development Documentation

Development history and implementation details are available in the [archived](archived/) folder.

## Quick Links

- **Main Repository**: [github.com/FOI-Bioinformatics/NanoPulse](https://github.com/FOI-Bioinformatics/NanoPulse)
- **Original NanoCLUST**: [github.com/genomicsITER/NanoCLUST](https://github.com/genomicsITER/NanoCLUST)
- **Issue Tracker**: [github.com/FOI-Bioinformatics/NanoPulse/issues](https://github.com/FOI-Bioinformatics/NanoPulse/issues)

## Key Features

### Production-Ready Pipeline
- 99/99 tests passing (100% coverage)
- 11 critical bugs fixed through real-data testing
- Validated with 5,147 ONT reads

### Novel Organism Detection
- Probabilistic classification system
- Rescue analysis for noise-classified reads
- Phylogenetic tree construction
- Optional phyloseq object generation

### Flexible Classification
- BLAST against NCBI databases
- Kraken2 taxonomic profiling
- FastANI reference-based classification

### Optimized Performance
- Memory-efficient dimensionality reduction (PCA/PaCMAP)
- Sparse matrix storage (99.70% compression)
- 8-16 GB system support
