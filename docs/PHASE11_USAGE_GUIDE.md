# Phase 11 Novel Diversity Detection - Usage Guide

This guide demonstrates how to use NanoPulse's Phase 11 features for detecting and analyzing potentially novel organisms in your amplicon sequencing data.

## Overview

Phase 11 combines four complementary approaches:

1. **Noise Point Rescue** (NanoASV-inspired) - Recovers low-abundance organisms
2. **Probabilistic Classification** (Emu-inspired) - Quantifies classification confidence
3. **Novel Sequence Extraction** - Automatically identifies potentially novel organisms
4. **Phylogenetics Integration** - Enables evolutionary context and R-based diversity analysis

## Quick Start

### Basic Novel Diversity Detection

```bash
nextflow run . \
    --input samplesheet.csv \
    --outdir results_novel_detection \
    --rescue_noise_points true \
    --use_probabilistic_classification true \
    --novelty_threshold 0.5 \
    --enable_blast true \
    --blast_db /path/to/nt
```

### With Phylogenetic Analysis

```bash
nextflow run . \
    --input samplesheet.csv \
    --outdir results_with_phylogeny \
    --rescue_noise_points true \
    --use_probabilistic_classification true \
    --novelty_threshold 0.5 \
    --build_phylotree true \
    --create_phyloseq true \
    --calculate_phylo_diversity true \
    --enable_blast true \
    --blast_db /path/to/nt
```

## Feature Descriptions

### 1. Noise Point Rescue

**What it does**: Applies secondary clustering to reads that HDBSCAN classified as noise (cluster_id = -1), recovering low-abundance organisms.

**When to use**: When you suspect low-abundance organisms are being missed.

**Parameters**:
```groovy
rescue_noise_points = true          // Enable noise rescue
noise_identity_threshold = 0.70     // Vsearch identity threshold (70% = relaxed)
noise_min_abundance = 5             // Minimum reads per rescued cluster
```

**Example**:
```bash
nextflow run . \
    --input samplesheet.csv \
    --rescue_noise_points true \
    --noise_identity_threshold 0.75 \
    --noise_min_abundance 10
```

**Expected output**:
- More clusters (especially small ones)
- Additional consensus sequences from noise-rescued clusters
- Improved capture of rare taxa

### 2. Probabilistic Classification

**What it does**: Uses Expectation-Maximization algorithm to compute classification confidence scores and identify potentially novel organisms.

**When to use**: When you want quantitative assessment of classification quality or suspect novel organisms.

**Parameters**:
```groovy
use_probabilistic_classification = true  // Enable EM algorithm
novelty_threshold = 0.5                  // Confidence threshold (0-1)
em_max_iterations = 50                   // Max EM iterations
em_convergence_threshold = 1e-6          // EM convergence criterion
```

**Example**:
```bash
nextflow run . \
    --input samplesheet.csv \
    --use_probabilistic_classification true \
    --novelty_threshold 0.6 \
    --em_max_iterations 100
```

**Outputs**:
- `consensus/*_annotations.tsv` - Includes confidence scores
- `classification/*_classification.json` - Detailed likelihood reports
- `novel_sequences/*.novel.fasta` - Low-confidence sequences
- `novel_sequences/*.novel_summary.tsv` - Novelty statistics

**Interpretation**:
- **Confidence > 0.8**: High-confidence classification (known organism)
- **Confidence 0.5-0.8**: Moderate confidence (review)
- **Confidence < 0.5**: Low confidence (potentially novel)

### 3. Confidence Visualization

**What it does**: Adds 3rd panel to UMAP plots showing confidence scores with color-coding.

**Automatically enabled** when `use_probabilistic_classification = true`

**Output**: `plots/*_umap_clustering.png` with 3 panels:
1. **Panel 1**: Clusters (colored by cluster ID)
2. **Panel 2**: Abundance (size by read count)
3. **Panel 3**: Confidence (Red = novel → Green = known)

**Interpretation**:
- **Green points**: High-confidence, well-characterized organisms
- **Yellow points**: Moderate confidence, review recommended
- **Red points**: Low confidence, potentially novel organisms

### 4. Novel Sequence Extraction

**What it does**: Automatically extracts consensus sequences with confidence below threshold for detailed analysis.

**Automatically enabled** when `use_probabilistic_classification = true`

**Parameters**:
```groovy
novelty_threshold = 0.5  // Confidence cutoff for novelty
```

**Outputs**:
- `novel_sequences/*.novel.fasta` - Sequences for further analysis
- `novel_sequences/*.novel_summary.tsv` - Statistics table

**Follow-up analysis**:
```bash
# BLAST novel sequences against nt
blastn -query novel_sequences/sample.novel.fasta \
       -db nt \
       -out novel_blast.txt \
       -outfmt 6 \
       -max_target_seqs 10

# Check if they're truly novel or just rare/divergent known taxa
```

### 5. Phylogenetic Tree Construction

**What it does**: Builds maximum likelihood phylogenetic tree using MAFFT + FastTree.

**When to use**: For evolutionary analysis or comparing novel sequences to known taxa.

**Parameters**:
```groovy
build_phylotree = true                   // Enable tree building
phylotree_alignment_method = 'auto'      // 'auto' (fast) or 'accurate' (slow)
```

**Example**:
```bash
nextflow run . \
    --input samplesheet.csv \
    --build_phylotree true \
    --phylotree_alignment_method accurate  // Use for publication-quality trees
```

**Outputs**:
- `phylogeny/*.tree` - Newick format tree
- `phylogeny/*.aln.fasta` - Multiple sequence alignment
- `phylogeny/*.tree_stats.txt` - Tree statistics

**Visualization** (in R or FigTree):
```r
library(ape)
tree <- read.tree("phylogeny/sample.tree")
plot(tree, type="phylogram", show.tip.label=TRUE)
```

### 6. Phyloseq Object Creation

**What it does**: Creates R phyloseq object combining tree + abundances + taxonomy for advanced diversity analysis.

**When to use**: For publication-quality diversity metrics and R-based analysis.

**Requirements**: `build_phylotree = true`

**Parameters**:
```groovy
create_phyloseq = true                  // Enable phyloseq creation
calculate_phylo_diversity = true        // Calculate diversity metrics
```

**Example**:
```bash
nextflow run . \
    --input samplesheet.csv \
    --build_phylotree true \
    --create_phyloseq true \
    --calculate_phylo_diversity true
```

**Outputs**:
- `phyloseq/*.rds` - phyloseq object
- `phyloseq/*_summary.txt` - Diversity metrics summary

**R Analysis**:
```r
library(phyloseq)
library(ggplot2)

# Load phyloseq object
ps <- readRDS("phyloseq/sample_phyloseq.rds")

# View summary
ps

# Access diversity metrics
sample_data(ps)$faiths_pd   # Faith's Phylogenetic Diversity
sample_data(ps)$shannon     # Shannon diversity
sample_data(ps)$simpson     # Simpson diversity

# Visualize phylogenetic tree
plot_tree(ps,
          color="Phylum",
          label.tips="Genus",
          ladderize="left",
          size="abundance")

# Calculate UniFrac distances (phylogeny-aware beta diversity)
unifrac_dist <- UniFrac(ps, weighted=TRUE)
pcoa_result <- ordinate(ps, method="PCoA", distance=unifrac_dist)

# Plot PCoA
plot_ordination(ps, pcoa_result, color="Phylum") +
    theme_bw() +
    ggtitle("PCoA - Weighted UniFrac Distance")
```

## Complete Workflow Example

### Scenario: Environmental Microbiome Study

You've sequenced 16S amplicons from a novel environmental sample and want to:
1. Detect all organisms (including rare ones)
2. Identify potentially novel species
3. Perform phylogenetic analysis
4. Generate publication-quality diversity metrics

```bash
# Full Phase 11 workflow
nextflow run . \
    --input samplesheet.csv \
    --outdir results_env_microbiome \
    \
    # Noise rescue for rare taxa
    --rescue_noise_points true \
    --noise_identity_threshold 0.75 \
    --noise_min_abundance 5 \
    \
    # Probabilistic classification for novelty detection
    --use_probabilistic_classification true \
    --novelty_threshold 0.6 \
    --em_max_iterations 100 \
    \
    # Phylogenetics for evolutionary context
    --build_phylotree true \
    --phylotree_alignment_method accurate \
    \
    # R integration for advanced analysis
    --create_phyloseq true \
    --calculate_phylo_diversity true \
    \
    # Classification databases
    --enable_blast true \
    --blast_db /path/to/nt \
    --enable_fastani true \
    --fastani_ref_dir /path/to/16S_refs \
    \
    # Execution profile
    --profile conda
```

### Results Interpretation

**1. Check UMAP visualization**:
```bash
open results_env_microbiome/plots/*_umap_clustering.png
```
- Look for red points (low confidence = potentially novel)
- Note cluster sizes and spatial distribution

**2. Review novel sequences**:
```bash
# Count potentially novel organisms
grep -c ">" results_env_microbiome/novel_sequences/*.novel.fasta

# View summary statistics
cat results_env_microbiome/novel_sequences/*.novel_summary.tsv
```

**3. Examine phylogenetic tree**:
```r
library(ape)
library(ggtree)

tree <- read.tree("results_env_microbiome/phylogeny/sample.tree")
annotations <- read.delim("results_env_microbiome/consensus/sample_annotations.tsv")

# Highlight low-confidence sequences
low_conf <- annotations$cluster_id[annotations$confidence < 0.6]
tree_tips_to_highlight <- paste0("cluster_", low_conf)

# Plot with highlighting
ggtree(tree) +
    geom_tiplab(aes(color = label %in% tree_tips_to_highlight)) +
    scale_color_manual(values = c("black", "red")) +
    theme_tree2()
```

**4. Analyze diversity metrics**:
```r
ps <- readRDS("results_env_microbiome/phyloseq/sample_phyloseq.rds")

# Get diversity summary
div_summary <- data.frame(
    Faith_PD = sample_data(ps)$faiths_pd,
    Shannon = sample_data(ps)$shannon,
    Simpson = sample_data(ps)$simpson,
    Richness = sample_data(ps)$observed_richness
)

print(div_summary)
```

## Parameter Optimization

### For Maximum Sensitivity (Detect Everything)

```groovy
# Aggressive noise rescue
rescue_noise_points = true
noise_identity_threshold = 0.65        // Very relaxed
noise_min_abundance = 3                // Accept very small clusters

# Strict novelty threshold
novelty_threshold = 0.7                // More sequences flagged as novel
```

### For High Confidence (Publication Quality)

```groovy
# Conservative noise rescue
rescue_noise_points = true
noise_identity_threshold = 0.85        // Stringent
noise_min_abundance = 10               // Larger clusters only

# Moderate novelty threshold
novelty_threshold = 0.5                // Balanced

# Accurate phylogenetics
phylotree_alignment_method = 'accurate'
```

### For Speed (Large Datasets)

```groovy
# Fast mode - disable optional features
rescue_noise_points = false            # Skip if not needed
build_phylotree = false                # Skip if not needed
create_phyloseq = false                # Skip if not needed
phylotree_alignment_method = 'auto'    # Fast alignment
```

## Troubleshooting

### Issue: No novel sequences detected

**Possible causes**:
1. Threshold too low - increase `novelty_threshold`
2. All sequences well-characterized - this is good!
3. Database incomplete - try multiple databases

**Solutions**:
```bash
# Lower threshold to capture more candidates
--novelty_threshold 0.3

# Use multiple classification methods
--enable_blast true --enable_fastani true
```

### Issue: Too many novel sequences

**Possible causes**:
1. Threshold too high
2. Poor database coverage
3. Contamination or sequencing errors

**Solutions**:
```bash
# Raise threshold
--novelty_threshold 0.7

# Check UMAP plot for clustering quality
# Examine top novel sequences manually
```

### Issue: Phylogenetic tree looks strange

**Possible causes**:
1. <3 consensus sequences (tree requires minimum 3)
2. Very divergent sequences
3. Alignment quality issues

**Solutions**:
```bash
# Use accurate alignment
--phylotree_alignment_method accurate

# Check alignment manually
cat phylogeny/*.aln.fasta
```

## Best Practices

1. **Always visualize first**: Check UMAP plots before diving into sequence analysis

2. **Use multiple classification methods**: Combine BLAST + FastANI for robust classification

3. **Validate novel sequences**: Low confidence ≠ novel species - could be:
   - Rare but known organisms
   - Divergent strains
   - Chimeric sequences
   - Sequencing errors

4. **Compare databases**: Try NCBI nt, SILVA, Greengenes, RDP

5. **Document parameters**: Record exact parameter values for reproducibility

6. **Backup results**: Phase 11 analysis generates many valuable intermediate files

## Citation

If you use Phase 11 features in your research, please cite:

- **NanoPulse**: [Pipeline publication pending]
- **UMAP**: McInnes et al. (2018) arXiv:1802.03426
- **HDBSCAN**: McInnes et al. (2017) JOSS 2:205
- **MAFFT**: Katoh & Standley (2013) Mol Biol Evol 30:772-780
- **FastTree**: Price et al. (2010) PLoS ONE 5:e9490
- **phyloseq**: McMurdie & Holmes (2013) PLoS ONE 8:e61217

## Support

For issues or questions:
- GitHub Issues: https://github.com/FOI-Bioinformatics/NanoPulse/issues
- Documentation: https://github.com/FOI-Bioinformatics/NanoPulse/docs

---

**Document Version**: 1.0 (2025-11-16)
**Pipeline Version**: NanoPulse 1.0dev
**Last Updated**: Phase 11 complete implementation
