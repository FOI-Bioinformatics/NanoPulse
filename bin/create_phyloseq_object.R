#!/usr/bin/env Rscript

#
# Create phyloseq object from NanoPulse outputs for downstream analysis in R
#
# This script combines phylogenetic tree, abundance table, and taxonomy
# annotations into a single phyloseq object for advanced diversity analysis.
#
# Usage:
#   create_phyloseq_object.R \
#       --tree phylotree.tree \
#       --abundance abundances.csv \
#       --taxonomy annotations.tsv \
#       --output sample_phyloseq.rds \
#       [--calculate-diversity]
#

suppressPackageStartupMessages({
    library(optparse)
    library(phyloseq)
    library(ape)
    library(picante)  # For Faith's PD
    library(vegan)    # For diversity indices
})

# Parse command-line arguments
option_list <- list(
    make_option(c("-t", "--tree"),
                type = "character",
                default = NULL,
                help = "Phylogenetic tree file (Newick format)",
                metavar = "FILE"),
    make_option(c("-a", "--abundance"),
                type = "character",
                default = NULL,
                help = "Abundance table (CSV format)",
                metavar = "FILE"),
    make_option(c("-x", "--taxonomy"),
                type = "character",
                default = NULL,
                help = "Taxonomy annotations (TSV format)",
                metavar = "FILE"),
    make_option(c("-o", "--output"),
                type = "character",
                default = "phyloseq_object.rds",
                help = "Output phyloseq object (RDS format) [default: %default]",
                metavar = "FILE"),
    make_option(c("-d", "--calculate-diversity"),
                action = "store_true",
                default = FALSE,
                help = "Calculate phylogenetic diversity metrics (Faith's PD, UniFrac)"),
    make_option(c("-v", "--verbose"),
                action = "store_true",
                default = FALSE,
                help = "Print verbose output")
)

parser <- OptionParser(
    usage = "%prog [options]",
    option_list = option_list,
    description = "Create phyloseq object from NanoPulse outputs"
)
args <- parse_args(parser)

# Validate required arguments
if (is.null(args$tree) || is.null(args$abundance) || is.null(args$taxonomy)) {
    print_help(parser)
    stop("Missing required arguments: --tree, --abundance, --taxonomy", call. = FALSE)
}

if (args$verbose) {
    cat("NanoPulse phyloseq Object Creator\n")
    cat("==================================\n\n")
}

# Read phylogenetic tree
if (args$verbose) {
    cat("Reading phylogenetic tree:", args$tree, "\n")
}

tree <- read.tree(args$tree)

# Check if tree is placeholder (empty tree for <3 sequences)
if (length(tree$tip.label) == 0 || is.null(tree$edge)) {
    cat("WARNING: Phylogenetic tree is empty (likely <3 consensus sequences)\n")
    cat("Skipping phyloseq object creation - minimum 3 sequences required\n")

    # Create placeholder output
    saveRDS(NULL, file = args$output)
    cat("\nCreated placeholder output:", args$output, "\n")
    quit(save = "no", status = 0)
}

if (args$verbose) {
    cat("  Tree has", length(tree$tip.label), "tips\n")
    cat("  Tree is rooted:", is.rooted(tree), "\n")
}

# Read abundance table
if (args$verbose) {
    cat("\nReading abundance table:", args$abundance, "\n")
}

abundance_df <- read.csv(args$abundance, stringsAsFactors = FALSE)

if (args$verbose) {
    cat("  Found", nrow(abundance_df), "clusters\n")
    cat("  Columns:", paste(colnames(abundance_df), collapse = ", "), "\n")
}

# Create OTU table (clusters × samples matrix)
# NanoPulse outputs have: cluster_id, read_count, relative_abundance
# We'll use read_count as the abundance value

otu_matrix <- as.matrix(abundance_df$read_count)
rownames(otu_matrix) <- paste0("cluster_", abundance_df$cluster_id)
colnames(otu_matrix) <- c("sample")  # Single sample per phyloseq object

otu_table <- otu_table(otu_matrix, taxa_are_rows = TRUE)

if (args$verbose) {
    cat("  Created OTU table:", nrow(otu_table), "taxa ×", ncol(otu_table), "samples\n")
}

# Read taxonomy annotations
if (args$verbose) {
    cat("\nReading taxonomy annotations:", args$taxonomy, "\n")
}

taxonomy_df <- read.table(
    args$taxonomy,
    sep = "\t",
    header = TRUE,
    stringsAsFactors = FALSE,
    quote = "",
    comment.char = ""
)

if (args$verbose) {
    cat("  Found", nrow(taxonomy_df), "annotated clusters\n")
    cat("  Columns:", paste(colnames(taxonomy_df), collapse = ", "), "\n")
}

# Parse taxonomy into standard ranks (Kingdom, Phylum, Class, Order, Family, Genus, Species)
# NanoPulse outputs have: cluster_id, classification, identity, alignment_length, evalue
# We'll extract taxonomy from the classification field

parse_taxonomy <- function(classification_string) {
    # Classification format varies by database
    # BLAST: "Bacteria; Proteobacteria; Gammaproteobacteria; ..."
    # Handle both semicolon and pipe separators

    if (is.na(classification_string) || classification_string == "unclassified") {
        return(data.frame(
            Kingdom = NA,
            Phylum = NA,
            Class = NA,
            Order = NA,
            Family = NA,
            Genus = NA,
            Species = NA,
            stringsAsFactors = FALSE
        ))
    }

    # Split by semicolon or pipe
    ranks <- strsplit(classification_string, "[;|]")[[1]]
    ranks <- trimws(ranks)

    # Create taxonomy data frame with standard ranks
    tax_df <- data.frame(
        Kingdom = ifelse(length(ranks) >= 1, ranks[1], NA),
        Phylum = ifelse(length(ranks) >= 2, ranks[2], NA),
        Class = ifelse(length(ranks) >= 3, ranks[3], NA),
        Order = ifelse(length(ranks) >= 4, ranks[4], NA),
        Family = ifelse(length(ranks) >= 5, ranks[5], NA),
        Genus = ifelse(length(ranks) >= 6, ranks[6], NA),
        Species = ifelse(length(ranks) >= 7, ranks[7], NA),
        stringsAsFactors = FALSE
    )

    return(tax_df)
}

# Parse all classifications
tax_list <- lapply(taxonomy_df$classification, parse_taxonomy)
tax_matrix <- do.call(rbind, tax_list)
rownames(tax_matrix) <- paste0("cluster_", taxonomy_df$cluster_id)

# Add additional annotation columns if present
if ("confidence" %in% colnames(taxonomy_df)) {
    tax_matrix$Confidence <- taxonomy_df$confidence
}
if ("identity" %in% colnames(taxonomy_df)) {
    tax_matrix$Identity <- taxonomy_df$identity
}

tax_table <- tax_table(as.matrix(tax_matrix))

if (args$verbose) {
    cat("  Created taxonomy table:", nrow(tax_table), "taxa ×", ncol(tax_table), "ranks\n")
}

# Align tip labels with OTU table rownames
# Tree tip labels should match cluster_N format
tree_tips <- tree$tip.label
otu_taxa <- rownames(otu_table)
tax_taxa <- rownames(tax_table)

# Find common taxa across all three objects
common_taxa <- Reduce(intersect, list(tree_tips, otu_taxa, tax_taxa))

if (args$verbose) {
    cat("\nAligning data:\n")
    cat("  Tree tips:", length(tree_tips), "\n")
    cat("  OTU table taxa:", length(otu_taxa), "\n")
    cat("  Taxonomy table taxa:", length(tax_taxa), "\n")
    cat("  Common taxa:", length(common_taxa), "\n")
}

if (length(common_taxa) == 0) {
    stop("No common taxa found across tree, OTU table, and taxonomy table", call. = FALSE)
}

# Subset all components to common taxa
tree_pruned <- keep.tip(tree, common_taxa)
otu_table_pruned <- prune_taxa(common_taxa, otu_table)
tax_table_pruned <- tax_table[common_taxa, , drop = FALSE]

if (args$verbose) {
    cat("  Pruned to", length(common_taxa), "common taxa\n")
}

# Create phyloseq object
phyloseq_obj <- phyloseq(
    otu_table_pruned,
    tax_table_pruned,
    phy_tree(tree_pruned)
)

if (args$verbose) {
    cat("\nCreated phyloseq object:\n")
    print(phyloseq_obj)
}

# Calculate phylogenetic diversity metrics (optional)
if (isTRUE(args$calculate_diversity)) {
    if (args$verbose) {
        cat("\nCalculating phylogenetic diversity metrics...\n")
    }

    diversity_metrics <- list()

    # Faith's Phylogenetic Diversity (PD)
    # Measures total phylogenetic branch length
    tryCatch({
        pd_result <- pd(
            t(otu_table(phyloseq_obj)),
            phy_tree(phyloseq_obj)
        )
        diversity_metrics$faiths_pd <- pd_result$PD[1]

        if (args$verbose) {
            cat("  Faith's PD:", round(diversity_metrics$faiths_pd, 3), "\n")
        }
    }, error = function(e) {
        cat("  WARNING: Could not calculate Faith's PD:", e$message, "\n")
    })

    # Shannon diversity index
    diversity_metrics$shannon <- diversity(
        t(otu_table(phyloseq_obj)),
        index = "shannon"
    )[1]

    if (args$verbose) {
        cat("  Shannon diversity:", round(diversity_metrics$shannon, 3), "\n")
    }

    # Simpson diversity index
    diversity_metrics$simpson <- diversity(
        t(otu_table(phyloseq_obj)),
        index = "simpson"
    )[1]

    if (args$verbose) {
        cat("  Simpson diversity:", round(diversity_metrics$simpson, 3), "\n")
    }

    # Observed richness (number of taxa)
    diversity_metrics$observed_richness <- sum(otu_table(phyloseq_obj) > 0)

    if (args$verbose) {
        cat("  Observed richness:", diversity_metrics$observed_richness, "taxa\n")
    }

    # Store diversity metrics in phyloseq object
    sample_data_df <- data.frame(
        sample = colnames(otu_table(phyloseq_obj)),
        faiths_pd = diversity_metrics$faiths_pd,
        shannon = diversity_metrics$shannon,
        simpson = diversity_metrics$simpson,
        observed_richness = diversity_metrics$observed_richness,
        stringsAsFactors = FALSE
    )
    rownames(sample_data_df) <- sample_data_df$sample

    sample_data(phyloseq_obj) <- sample_data(sample_data_df)

    if (args$verbose) {
        cat("\nUpdated phyloseq object with diversity metrics:\n")
        print(phyloseq_obj)
    }
}

# Save phyloseq object
saveRDS(phyloseq_obj, file = args$output)

if (args$verbose) {
    cat("\nPhyloseq object saved to:", args$output, "\n")
    cat("\nTo load in R:\n")
    cat("  library(phyloseq)\n")
    cat("  ps <- readRDS('", args$output, "')\n", sep = "")
    cat("  plot_tree(ps, color='Phylum', label.tips='Genus')\n")
}

# Create summary text file
summary_file <- sub("\\.rds$", "_summary.txt", args$output)
sink(summary_file)
cat("NanoPulse phyloseq Object Summary\n")
cat("==================================\n\n")
cat("Created:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")
cat("Input files:\n")
cat("  Tree:", args$tree, "\n")
cat("  Abundance:", args$abundance, "\n")
cat("  Taxonomy:", args$taxonomy, "\n\n")
cat("Phyloseq object contents:\n")
print(phyloseq_obj)
cat("\n")

if (isTRUE(args$calculate_diversity)) {
    cat("Diversity metrics:\n")
    cat("  Faith's Phylogenetic Diversity:", round(diversity_metrics$faiths_pd, 3), "\n")
    cat("  Shannon diversity:", round(diversity_metrics$shannon, 3), "\n")
    cat("  Simpson diversity:", round(diversity_metrics$simpson, 3), "\n")
    cat("  Observed richness:", diversity_metrics$observed_richness, "taxa\n")
}

sink()

if (args$verbose) {
    cat("Summary written to:", summary_file, "\n")
}
