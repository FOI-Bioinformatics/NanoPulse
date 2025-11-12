# NanoPulse Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v1.0dev] - Work in Progress

### Added

- Complete DSL2 migration from NanoCLUST
- nf-core compliance improvements
- Comprehensive nf-test test suite (79 tests)
- Module and subworkflow meta.yml documentation
- Updated dependencies to latest versions
- Nextflow requirement >= 25.10.0
- Parameter validation with nf-schema
- Modular DSL2 structure with:
  - 13 local modules (kmerfreq, umap, hdbscan, splitclusters, canu_correct, draft_selection, racon_iterative, medaka, classify_consensus, fastani_classify, getabundances, joinconsensus, plotresults)
  - 4 local subworkflows (per_cluster_assembly, classify_clusters, validate_databases, utils_nfcore_nanopulse_pipeline)
  - 3 nf-core modules (fastqc, multiqc, nanoplot)
  - 1 nf-core subworkflow (utils_nfcore_pipeline)
- modules.json for nf-core module tracking
- Comprehensive configuration structure (modules.config, base.config, test.config)

### Changed

- Migrated from DSL1 to DSL2 syntax
- Pipeline name from NanoCLUST to NanoPulse
- Repository organization from genomicsITER to FOI-Bioinformatics
- Updated pipeline structure to follow nf-core standards
- Reorganized configuration files for DSL2
- Updated conda package versions:
  - pandas: 1.1.1 → 2.3.3
  - matplotlib-base: 3.3.1 → 3.10.7
  - requests: 2.24.0 → 2.32.5
  - fastp: 0.20.1 → 1.0.1
  - canu: 2.0 → 2.3
  - medaka: 1.0.3 → 2.1.1
  - blast: 2.10.1 → 2.16.0
  - minimap2: 2.17 → 2.30
  - racon: 1.4.13 → 1.5.0
  - fastqc: 0.11.9 → 0.12.1
  - multiqc: 1.9 → 1.32
  - porechop → porechop_abi: 0.5.1
  - And more...
- Manifest configuration updated to reflect FOI-Bioinformatics organization
- Schema updated with proper GitHub repository URLs

### Removed

- DSL1 legacy code and artifacts:
  - `lib/WorkflowNanoclust.groovy`
  - `main.nf.dsl1.backup`
  - `bin/markdown_to_html.r`
- Old markdown-format GitHub issue templates
- Deprecated nanoclust branding assets

### Fixed

- Parameter validation and schema compliance
- Module configuration structure
- Test infrastructure setup
- nf-core lint compliance (202 of 241 tests passing)
- Plugin consistency (switched from nf-validation to nf-schema)
- YAML parsing errors in subworkflow meta.yml files
- Process config selectors for DSL2

### Dependencies

All dependencies updated to latest compatible versions as of November 2025.
See conda environment files in `conda_envs/` for detailed version information.

---

## Project History

This pipeline was originally based on [NanoCLUST](https://github.com/genomicsITER/NanoCLUST)
and has been adapted, modernized, and rebranded as NanoPulse for DSL2 and nf-core compliance.

### Original Credits

- Original authors: Hector Rodriguez-Perez, Laura Ciuffreda
- Original repository: [genomicsITER/NanoCLUST](https://github.com/genomicsITER/NanoCLUST)

### NanoPulse Maintainers

- FOI-Bioinformatics Team
- Repository: [FOI-Bioinformatics/NanoPulse](https://github.com/FOI-Bioinformatics/NanoPulse)
