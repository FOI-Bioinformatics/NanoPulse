# Comprehensive Evaluation: NanoPulse vs Pike

## Executive Summary

This document provides a comprehensive comparison of two Oxford Nanopore amplicon sequencing analysis pipelines: **NanoPulse** (locally developed, based on NanoCLUST) and **Pike** (https://github.com/DanilKrivonos/Pike).

### Quick Comparison Overview

| **Category** | **NanoPulse** | **Pike** | **Winner** |
|--------------|---------------|----------|------------|
| **Scientific Validation** | Peer-reviewed (Bioinformatics 2021) | No publication | **NanoPulse** |
| **Workflow Architecture** | Nextflow with parallel execution | Standalone Python CLI | **NanoPulse** (scalability) |
| **Target Amplicon Length** | 1400-1700 bp (full-length 16S) | 350-600 bp (shorter amplicons) | **Different use cases** |
| **Consensus Building** | 5-step (Canu+fastANI+Racon+Medaka) | 2-step (MAFFT+Medaka) | **NanoPulse** (thoroughness) |
| **Installation Complexity** | High (Nextflow+Docker/14 Conda envs) | Low (1 Conda env + pip) | **Pike** (ease) |
| **Documentation** | Comprehensive with paper | Basic, incomplete | **NanoPulse** |
| **Demultiplexing** | Built-in (qcat/Porechop) | Not available | **NanoPulse** |
| **Primer Trimming** | Not built-in | Cutadapt (2 rounds) | **Pike** |
| **Community Support** | Active, nf-core inspired | Minimal (last commit Aug 2023) | **NanoPulse** |
| **Computational Cost** | Higher (more steps) | Lower (fewer steps) | **Pike** (speed) |

---

## Table 1: Pipeline Architecture & Technology

| **Dimension** | **NanoPulse** | **Pike** | **Advantage** |
|--------------|---------------|----------|---------------|
| **Workflow Manager** | Nextflow (DSL1, ≥0.32.0) | None (Standalone Python CLI) | NanoPulse - Better for HPC/cluster environments |
| **Execution Model** | Parallel process execution with automatic resource management | Sequential Python script execution | NanoPulse - More scalable |
| **Containerization** | Docker (14 containers) + Singularity + Conda (14 envs) | Single Conda env + pip package | NanoPulse - Better reproducibility |
| **Programming Language** | Nextflow + Python + Bash | Pure Python (100%) | Pike - Simpler codebase |
| **Resource Management** | Dynamic retry with increased resources, configurable max_memory/cpus/time | Thread-based, manual configuration | NanoPulse - More robust |
| **Parallelization** | Process-level + per-cluster parallel processing | Thread-based within single process | NanoPulse - Higher throughput |
| **Error Handling** | Automatic retry mechanisms, exit code handling | Basic Python exceptions | NanoPulse - More resilient |
| **Distribution Model** | Git clone + Nextflow execution | PyPI package (`pike-meta`) | Pike - Easier installation |

---

## Table 2: Scientific Validation & Community

| **Dimension** | **NanoPulse** | **Pike** | **Advantage** |
|--------------|---------------|----------|---------------|
| **Peer Review Status** | ✅ Published (Bioinformatics 2021, Vol 37, Issue 11) | ❌ No publication | NanoPulse - Scientifically validated |
| **Benchmarking** | ✅ Validated on commercial mock communities vs state-of-art tools | ❌ No documented benchmarks | NanoPulse - Performance proven |
| **GitHub Stars** | Not available (local repo) | 2 stars | Inconclusive |
| **GitHub Forks** | Not available (local repo) | 0 forks | Inconclusive |
| **Community Support** | nf-core inspired, active development | Minimal community engagement | NanoPulse - Better support |
| **Last Commit** | Recent (visible in dev branch) | August 17, 2023 (~16 months ago) | NanoPulse - Actively maintained |
| **Development Status** | Active (v1.0dev) | Maintenance mode | NanoPulse - Ongoing development |
| **License** | MIT | MIT | Equal |
| **CI/CD Testing** | ✅ GitHub Actions (Nextflow 19.10.0 + latest) | ❌ No visible CI/CD | NanoPulse - Better quality assurance |

---

## Table 3: Input/Output Capabilities

| **Dimension** | **NanoPulse** | **Pike** | **Advantage** |
|--------------|---------------|----------|---------------|
| **Input Format** | FASTQ (single or pooled) | FASTQ (directory-based) | Equal |
| **Demultiplexing** | ✅ Built-in (qcat or Porechop) with 6+ barcode kits | ❌ Not mentioned | NanoPulse - Handles barcoded samples |
| **Primer Trimming** | ❌ Not explicitly mentioned | ✅ Cutadapt (2 rounds) | Pike - Better for primer removal |
| **Target Amplicon Length** | 1400-1700 bp (full-length 16S) | 350-600 bp (variable amplicons) | **Different use cases** |
| **Output Formats** | FASTA, TSV, CSV, PNG, HTML, ZIP | FASTQ, FASTA, TSV, PDF | NanoPulse - More comprehensive |
| **Quality Reports** | ✅ FastQC + MultiQC | ❌ Not mentioned | NanoPulse - Better QC reporting |
| **Abundance Tables** | ✅ Family, Genus, Species levels | ✅ OTU table | NanoPulse - Multi-level taxonomy |
| **Visualizations** | UMAP plots, abundance plots, pipeline DAG | Clustering visualizations (PDF) | NanoPulse - More comprehensive |
| **Database Requirements** | Local BLAST DB + taxdb (mandatory for full pipeline) | User-provided (optional for taxonomy) | Pike - More flexible |

---

## Table 4: Workflow Stages & Tool Comparison

| **Stage** | **NanoPulse** | **Pike** | **Notes** |
|-----------|---------------|----------|-----------|
| **Demultiplexing** | qcat / Porechop | Not included | NanoPulse has built-in support |
| **Primer Trimming** | Not included | Cutadapt v4.6 (2 rounds) | Pike has explicit primer handling |
| **Quality Filtering** | fastp v0.20.1 (Q≥8, length-based) | Filtlong v0.2.1 (median Q, length-based) | Different tools, similar goals |
| **Quality Assessment** | FastQC + MultiQC | Not included | NanoPulse provides QC reports |
| **K-mer Calculation** | Custom Python script (k=5, log-normalized, 32 threads) | Built-in (k=6) | Different k-mer sizes |
| **Dimensionality Reduction** | UMAP (n_neighbors=15, min_dist=0.1) | UMAP (n_neighbors=30) | Pike uses more neighbors |
| **Clustering** | HDBSCAN (min_size=50-100, epsilon=0.5) | HDBSCAN (min_size=30) | NanoPulse more stringent by default |
| **Read Correction** | Canu v2.0 (genomeSize=1.5k) | Not included | NanoPulse has error correction step |
| **Draft Selection** | fastANI v1.31 (all-vs-all ANI) | Not included | NanoPulse has sophisticated draft selection |
| **Alignment** | minimap2 v2.17 (for polishing) | MAFFT (for consensus) | Different strategies |
| **Consensus Polishing** | Racon v1.4.13 → Medaka v1.0.3 | Medaka v1.11.3 only | Pike uses newer Medaka, NanoPulse has 2-stage polishing |
| **Taxonomy Assignment** | BLASTN (BLAST v2.10.1, max 5 targets) | BLASTN (user-configured) | Similar approach |
| **Abundance Calculation** | Custom Python + Unipept API | OTU counting | NanoPulse provides taxonomic breakdown |

---

## Table 5: Clustering Methodology Deep Dive

| **Parameter** | **NanoPulse** | **Pike** | **Impact** |
|---------------|---------------|----------|------------|
| **K-mer Size** | k=5 | k=6 | Pike may capture more sequence context |
| **K-mer Processing** | Log-normalized, forward + reverse complement | Not specified | NanoPulse explicit normalization |
| **Feature Space** | K-mer frequency vectors | K-mer frequency vectors | Same approach |
| **UMAP Neighbors** | 15 | 30 | Pike creates denser neighborhood graphs |
| **UMAP min_dist** | 0.1 | Not specified (default 0.1) | Likely similar |
| **UMAP Dimensions** | 2D | Not specified (likely 2D) | Assumed similar |
| **Clustering Algorithm** | HDBSCAN | HDBSCAN | Same algorithm |
| **Min Cluster Size** | 50-100 (configurable) | 30 | NanoPulse more conservative (fewer small clusters) |
| **Cluster Selection** | epsilon=0.5 | Not specified | NanoPulse configurable |
| **Default Read Subset** | 100,000 reads | Configurable via usereads | NanoPulse explicit default |
| **Scalability** | Memory warning for large datasets | Not documented | NanoPulse provides guidance |

---

## Table 6: Consensus Building Strategy

| **Aspect** | **NanoPulse** | **Pike** | **Comparison** |
|------------|---------------|----------|----------------|
| **Step 1** | Canu error correction (100 reads/cluster) | MAFFT multiple sequence alignment | NanoPulse: read-level correction; Pike: alignment-based |
| **Step 2** | fastANI draft selection (highest avg ANI) | Medaka polishing | NanoPulse selects best representative first |
| **Step 3** | Minimap2 mapping to draft | Quality filtering (Q≥15) | Different validation approaches |
| **Step 4** | Racon polishing (Q≥9) | - | NanoPulse has intermediate polishing |
| **Step 5** | Medaka polishing (r941_min_high_g303) | - | NanoPulse has final polishing |
| **Polishing Rounds** | 2 (Racon + Medaka) | 1 (Medaka only) | NanoPulse more thorough |
| **Medaka Version** | v1.0.3 (older, stable) | v1.11.3 (newer) | Pike uses more recent version |
| **Medaka Model** | r941_min_high_g303 (R9.4.1 specific) | Not specified | NanoPulse flow cell specific |
| **Quality Threshold** | Racon Q≥9, general filtering Q≥8 | Letter Q≥15 (positions below → 'N') | Pike more stringent on final consensus |
| **Minimum Support** | polishing_reads=100 | consensus_seq_lim (configurable) | Both filter low-coverage clusters |
| **Computational Cost** | High (5 steps with alignment/polishing) | Low (1-2 steps) | Pike faster, NanoPulse more accurate (likely) |

---

## Table 7: Configuration & Flexibility

| **Configuration Type** | **NanoPulse** | **Pike** | **Flexibility** |
|------------------------|---------------|----------|-----------------|
| **Analysis Modes** | Single-sample or pooled (via demux) | `--mode single` or `--mode pool` | Pike explicit, NanoPulse implicit |
| **Clustering Parameters** | 3 params (umap_set_size, min_cluster_size, cluster_sel_epsilon) | 3 params (umap_neighbours, cluster_size, k) | Equal |
| **Read Length Filters** | min_read_length, max_read_length | -minlen, -maxlen | Equal |
| **Quality Thresholds** | Implicit in fastp (Q≥8) | -read_q_score (configurable) | Pike more explicit control |
| **Polishing Control** | polishing_reads parameter | -consensus_seq_lim, -letter_Q_lim | Pike more granular |
| **Resource Limits** | max_memory, max_cpus, max_time | -threads only | NanoPulse more comprehensive |
| **Database Options** | --db (local BLAST), --tax (taxdb) | User-provided via command | Similar flexibility |
| **Barcoding Kits** | 6+ kits supported (RAB204, RBK004, etc.) | N/A | NanoPulse only |
| **Profile System** | Nextflow profiles (test, docker, conda, custom) | Conda env + runtime args | NanoPulse more sophisticated |
| **Output Directory** | --outdir | -output | Equal |
| **Read Limit** | umap_set_size (for clustering subset) | -usereads (per sample max) | Different purposes |

---

## Table 8: Performance & Scalability

| **Metric** | **NanoPulse** | **Pike** | **Assessment** |
|------------|---------------|----------|----------------|
| **Memory (Default)** | 32-36 GB for 100K reads | Not documented | NanoPulse provides estimates |
| **Memory (Reduced)** | 10-13 GB for 50K reads | Not documented | NanoPulse has tested configurations |
| **CPU Usage** | Multi-core parallel (default 16 max, benefits from more) | Configurable threads | Both support parallelization |
| **Test Dataset Performance** | Runs on 4 cores, 16 GB RAM | Not documented | NanoPulse provides minimal specs |
| **Scalability Strategy** | Automatic resource retry, configurable limits | Manual thread adjustment | NanoPulse more automated |
| **Bottlenecks** | read_clustering (high memory), Canu (slow) | Not documented | NanoPulse identifies pain points |
| **Runtime (Estimated)** | Hours to days (depends on cluster count) | Not documented | No direct comparison possible |
| **I/O Optimization** | Parallel cluster processing reduces serial I/O | Sequential processing likely | NanoPulse advantage |
| **Known Issues** | Conda compatibility, sudo requirements for clustering | None documented | NanoPulse more transparent |
| **Error Recovery** | Automatic retry with 2x memory on OOM (exit 137/140) | Not documented | NanoPulse more robust |

---

## Table 9: Installation & Dependencies

| **Aspect** | **NanoPulse** | **Pike** | **Ease of Use** |
|------------|---------------|----------|-----------------|
| **Installation Steps** | 1. Install Nextflow<br>2. Clone repo<br>3. Pull Docker/setup Conda<br>4. Download databases | 1. Create conda env (medaka, cutadapt, filtlong)<br>2. pip install pike-meta<br>3. Setup databases (optional) | Pike simpler (2-3 steps vs 4) |
| **Container Support** | ✅ Docker (recommended) + Singularity | ❌ Conda only | NanoPulse better reproducibility |
| **Total Dependencies** | 14 conda environments OR 14 Docker containers | 1 conda env + pip package | Pike much simpler |
| **Dependency Conflicts** | Isolated per-process envs (low risk) | Single env (medium risk) | NanoPulse more isolated |
| **Database Download** | Manual (NCBI 16S ~1 GB + taxdb ~500 MB) | User-provided (optional) | Pike more flexible |
| **Disk Space (Tools)** | High (14 conda envs or containers) | Low (single env) | Pike advantage |
| **Internet Requirements** | Initial download + optional remote BLAST | Initial installation only | Similar |
| **System Permissions** | May require sudo for clustering (known issue) | Standard user (assumed) | Pike advantage |
| **Version Pinning** | Explicit in container/conda recipes | Medaka=1.11.3, Cutadapt=4.6, Filtlong=0.2.1 | Both good reproducibility |
| **Update Mechanism** | Git pull + rebuild containers/envs | pip install --upgrade pike-meta | Pike easier updates |

---

## Table 10: Documentation & Usability

| **Dimension** | **NanoPulse** | **Pike** | **Quality** |
|---------------|---------------|----------|-------------|
| **README Completeness** | ✅ Comprehensive | ⚠️ Basic, incomplete sections | NanoPulse superior |
| **Usage Guide** | ✅ Detailed (docs/2usage.md) | ✅ Basic examples | NanoPulse more thorough |
| **Output Documentation** | ✅ Detailed (docs/3pipeline_output.md) | ⚠️ Mentioned but not detailed | NanoPulse better |
| **Parameter Reference** | ✅ Detailed with defaults | ✅ Basic descriptions | NanoPulse more complete |
| **Troubleshooting** | ⚠️ Some issues documented in README | ❌ Not provided | NanoPulse better |
| **Examples** | ✅ Multiple (test profile, full run) | ✅ Basic single/pool mode | NanoPulse more diverse |
| **Installation Guide** | ✅ Comprehensive | ✅ Clear and simple | Equal |
| **Publication/Citation** | ✅ Peer-reviewed paper | ❌ "Add later" placeholder | NanoPulse scientifically backed |
| **Algorithm Description** | ✅ Detailed in paper + docs | ⚠️ Basic in README | NanoPulse more transparent |
| **API Documentation** | N/A (workflow, not library) | ❌ Not provided | N/A |
| **Changelog** | ⚠️ Minimal | ❌ Not provided | Both lacking |
| **Code Comments** | ⚠️ Some TODO comments remain | Not assessed | Needs review |
| **User Community** | nf-core community resources | Minimal | NanoPulse advantage |

---

## Evaluation Plan

### Phase 1: Functional Testing (Recommended)

**1. Test Dataset Preparation**
- Use NanoPulse test dataset (mock4_run3bc08_5000.fastq)
- Generate synthetic datasets at multiple scales (5K, 10K, 50K, 100K reads)
- Include samples requiring demultiplexing (for NanoPulse only)

**2. Run Both Pipelines**
- Execute NanoPulse with test profile
- Execute Pike with comparable parameters
- Document all commands and configurations used

**3. Output Comparison**
- Compare clustering results (number of clusters, cluster sizes)
- Compare consensus sequence quality (length, completeness)
- Compare taxonomy assignments (if using same reference DB)
- Compare computational resource usage

### Phase 2: Performance Benchmarking (Optional)

**1. Runtime Analysis**
- Measure wall-clock time for each major stage
- Profile memory usage over time
- Assess CPU utilization

**2. Scalability Testing**
- Test with increasing read counts (10K → 100K → 500K)
- Measure resource scaling behavior

### Phase 3: Accuracy Assessment (Requires Mock Community)

**1. Ground Truth Comparison**
- Use mock community with known composition
- Compare detected OTUs to expected species
- Calculate precision, recall, F1 scores

### Phase 4: Use Case Alignment

**1. Amplicon Length Compatibility**
- NanoPulse: Best for full-length 16S (1400-1700 bp)
- Pike: Best for shorter amplicons (350-600 bp)
- Document which use cases each pipeline serves

**2. Workflow Integration**
- NanoPulse: Better for HPC environments with Nextflow
- Pike: Better for standalone workstations or simple analyses

---

## Recommendations

### Choose **NanoPulse** if you need:

✅ **Full-length 16S rRNA sequencing (1400-1700 bp)**
✅ **Scientifically validated, peer-reviewed methods**
✅ **Built-in demultiplexing for barcoded samples**
✅ **Comprehensive QC reports (FastQC, MultiQC)**
✅ **HPC/cluster execution with resource management**
✅ **More sophisticated consensus building (Canu + fastANI + Racon + Medaka)**
✅ **Multi-level taxonomic abundance tables**
✅ **Active development and community support**
✅ **Automatic error recovery and resource scaling**
✅ **Better documentation and scientific backing**

### Choose **Pike** if you need:

✅ **Shorter amplicons (350-600 bp, e.g., hypervariable regions)**
✅ **Simple standalone Python tool (no workflow manager)**
✅ **Explicit primer trimming (Cutadapt)**
✅ **Newer Medaka version (v1.11.3)**
✅ **Faster installation (pip package)**
✅ **Lower computational overhead**
✅ **Joint clustering across samples (pool mode)**
✅ **Simpler dependency management**

### Critical Gaps in Pike:

❌ **No scientific validation/publication**
❌ **No performance benchmarks**
❌ **Limited community support**
❌ **Appears unmaintained (no commits since Aug 2023)**
❌ **Incomplete documentation**
❌ **No CI/CD testing infrastructure**

---

## Key Insights

### Algorithmic Differences

**NanoPulse Strengths:**
- More thorough error correction with Canu
- Intelligent draft selection using fastANI (all-vs-all ANI comparison)
- Two-stage polishing (Racon → Medaka)
- More conservative clustering (min_cluster_size 50-100 vs 30)

**Pike Strengths:**
- Explicit primer handling (2 rounds of Cutadapt)
- More recent Medaka version
- Simpler alignment-based consensus (MAFFT)
- More relaxed clustering parameters (may detect more OTUs)

### Use Case Differentiation

**NanoPulse is designed for:**
- Full-length 16S amplicon sequencing
- High-accuracy species-level identification
- Barcoded multiplex sequencing runs
- HPC/cluster computing environments
- Research requiring peer-reviewed methodology

**Pike is designed for:**
- Variable amplicon lengths (especially shorter)
- Quick exploratory analyses
- Standalone workstation execution
- Projects with explicit primer sequences
- Simpler workflow requirements

### Technical Maturity

**NanoPulse:**
- Mature, peer-reviewed pipeline (2021 publication)
- Active development and maintenance
- Comprehensive testing infrastructure
- nf-core community alignment
- Known issues documented and tracked

**Pike:**
- Newer tool (based on commit history)
- Development appears stalled (Aug 2023 last commit)
- No formal validation or benchmarking
- Minimal community engagement
- Incomplete documentation

---

## Conclusion

**NanoPulse** emerges as the more mature, scientifically validated, and feature-rich solution, particularly suited for **full-length 16S rRNA sequencing** in research environments requiring robust, reproducible workflows with comprehensive QC and taxonomic profiling.

**Pike** offers a simpler, more accessible alternative for **shorter amplicon analysis** with lower computational overhead, but lacks scientific validation and active maintenance.

For production research workflows, **NanoPulse is the recommended choice** due to its peer-reviewed methodology, active development, comprehensive documentation, and proven performance on mock communities. Pike may be suitable for exploratory analyses or specific use cases requiring shorter amplicon support, but users should be aware of its limitations regarding validation and maintenance status.

---

**Document Version:** 1.0
**Date:** 2025-11-12
**Analysis Based On:**
- NanoPulse: Local repository at `/Users/andreassjodin/Code/NanoPulse` (dev branch)
- Pike: GitHub repository https://github.com/DanilKrivonos/Pike (as of analysis date)
