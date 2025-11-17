/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// QC modules
include { FASTQC                  } from '../modules/nf-core/fastqc/main'
include { NANOPLOT                } from '../modules/nf-core/nanoplot/main'

// Clustering modules
include { SEQTK_SAMPLE            } from '../modules/local/seqtk_sample/main'
include { KMERFREQ                } from '../modules/local/kmerfreq/main'
include { PCA                     } from '../modules/local/pca/main'
include { UMAP                    } from '../modules/local/umap/main'
include { PACMAP                  } from '../modules/local/pacmap/main'
include { HDBSCAN                 } from '../modules/local/hdbscan/main'
include { RESCUE_NOISE            } from '../modules/local/rescue_noise/main'
include { SPLITCLUSTERS           } from '../modules/local/splitclusters/main'

// Assembly & polishing subworkflow
include { PER_CLUSTER_ASSEMBLY    } from '../subworkflows/local/per_cluster_assembly/main'

// Classification subworkflows
include { VALIDATE_DATABASES      } from '../subworkflows/local/validate_databases/main'
include { CLASSIFY_CLUSTERS       } from '../subworkflows/local/classify_clusters/main'

// Utility modules
include { JOINCONSENSUS             } from '../modules/local/joinconsensus/main'
include { GETABUNDANCES             } from '../modules/local/getabundances/main'
include { PLOTRESULTS               } from '../modules/local/plotresults/main'
include { AGGREGATE_CLASSIFICATIONS } from '../modules/local/aggregate_classifications/main'
include { EXTRACT_NOVEL_SEQUENCES   } from '../modules/local/extract_novel_sequences/main'
include { BUILD_PHYLOTREE           } from '../modules/local/build_phylotree/main'
include { CREATE_PHYLOSEQ           } from '../modules/local/create_phyloseq/main'

// MultiQC
include { MULTIQC                 } from '../modules/nf-core/multiqc/main'

// Helper functions
include { paramsSummaryMap        } from 'plugin/nf-schema'
include { paramsSummaryMultiqc    } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML  } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText  } from '../subworkflows/local/utils_nfcore_nanopulse_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOW: NANOPULSE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow NANOPULSE {

    take:
    ch_samplesheet // channel: samplesheet read in from --input

    main:

    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

    //
    // Create channels from samplesheet
    //
    ch_reads = ch_samplesheet
        .map { meta, reads ->
            // Ensure meta has required fields
            def new_meta = meta + [
                single_end: true  // NanoPulse processes single-end reads
            ]
            [new_meta, reads]
        }

    //
    // Optional: Quality Control
    //
    if (params.multiqc) {
        // Run FastQC if requested
        FASTQC(ch_reads)
        ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip)
        ch_versions = ch_versions.mix(FASTQC.out.versions.first())

        // Run NanoPlot for ONT-specific QC
        NANOPLOT(ch_reads)
        ch_multiqc_files = ch_multiqc_files.mix(NANOPLOT.out.txt)
        ch_versions = ch_versions.mix(NANOPLOT.out.versions.first())
    }

    //
    // Validate classification databases
    //
    VALIDATE_DATABASES()

    //
    // STEP 1: Subsample reads for clustering (if needed)
    //
    SEQTK_SAMPLE(
        ch_reads,
        params.umap_set_size
    )
    ch_versions = ch_versions.mix(SEQTK_SAMPLE.out.versions.first())

    //
    // STEP 2: K-mer frequency calculation
    //
    KMERFREQ(
        SEQTK_SAMPLE.out.reads,
        params.kmer_size
    )
    ch_versions = ch_versions.mix(KMERFREQ.out.versions.first())

    //
    // STEP 2a: Optional PCA preprocessing (Phase 2 optimization)
    //
    // PCA reduces 131,072 k-mer features → 50 principal components
    // Memory impact: 105 GB → 40 MB (99.96% reduction)
    // Quality: Preserves >99% variance (lossless)
    //
    ch_dimred_input = Channel.empty()

    if (params.enable_pca) {
        // Combine NPZ data and metadata files for PCA input
        ch_pca_input = KMERFREQ.out.freqs_npz
            .join(KMERFREQ.out.freqs_meta, by: 0)

        PCA(
            ch_pca_input,
            params.pca_n_components
        )
        ch_versions = ch_versions.mix(PCA.out.versions.first())
        ch_dimred_input = PCA.out.features
    } else {
        ch_dimred_input = KMERFREQ.out.freqs_tsv
    }

    //
    // STEP 2b: Dimensionality reduction (UMAP or PaCMAP)
    //
    // Algorithm selection via params.dimreduction_algorithm:
    // - 'umap': Standard UMAP (default, proven method)
    // - 'pacmap': PaCMAP (2-3x faster, lower memory, better structure preservation)
    //
    ch_embedding_coords = Channel.empty()
    ch_embedding_plot = Channel.empty()

    if (params.dimreduction_algorithm == 'pacmap') {
        PACMAP(
            ch_dimred_input,
            params.umap_dimensions,      // PaCMAP uses same dimensionality
            params.umap_neighbors        // Same neighbor parameter
        )
        ch_versions = ch_versions.mix(PACMAP.out.versions.first())
        ch_embedding_coords = PACMAP.out.coords
        ch_embedding_plot = PACMAP.out.plot
    } else {
        UMAP(
            ch_dimred_input,
            params.umap_dimensions,
            params.umap_neighbors,
            params.umap_min_dist
        )
        ch_versions = ch_versions.mix(UMAP.out.versions.first())
        ch_embedding_coords = UMAP.out.coords
        ch_embedding_plot = UMAP.out.plot
    }

    //
    // STEP 3: HDBSCAN clustering
    //
    HDBSCAN(
        ch_embedding_coords,
        params.min_cluster_size,
        params.min_samples,
        params.cluster_sel_epsilon
    )
    ch_versions = ch_versions.mix(HDBSCAN.out.versions.first())

    //
    // STEP 3b: Rescue HDBSCAN noise points (optional)
    //
    // NanoASV-inspired approach: Apply secondary clustering to noise points (cluster_id = -1)
    // using vsearch with relaxed parameters (70% identity, min 5 reads). This recovers
    // low-abundance clusters that HDBSCAN classified as noise.
    //
    ch_final_clusters = Channel.empty()

    if (params.rescue_noise_points) {
        RESCUE_NOISE(
            ch_reads.join(HDBSCAN.out.clusters, by: 0),
            params.noise_identity_threshold,
            params.noise_min_abundance
        )
        ch_versions = ch_versions.mix(RESCUE_NOISE.out.versions.first())
        ch_final_clusters = RESCUE_NOISE.out.clusters
    } else {
        // Use original HDBSCAN clusters if rescue is disabled
        ch_final_clusters = HDBSCAN.out.clusters
    }

    //
    // STEP 4: Split reads by cluster
    //
    SPLITCLUSTERS(
        ch_reads.join(ch_final_clusters, by: 0)
    )
    ch_versions = ch_versions.mix(SPLITCLUSTERS.out.versions.first())

    //
    // CRITICAL: Transpose cluster files and enrich meta with cluster_id
    //
    // Input:  [meta, [cluster_0.fastq, cluster_1.fastq, ...]]
    // Output: [[meta + cluster_id: 0], cluster_0.fastq], [[meta + cluster_id: 1], cluster_1.fastq], ...
    //
    ch_per_cluster_reads = SPLITCLUSTERS.out.clustered_reads
        .transpose()  // Split list into individual emissions
        .map { meta, cluster_file ->
            // Extract cluster ID from filename
            def cluster_id = cluster_file.simpleName.replaceAll('cluster_', '')

            // Create new meta with cluster_id
            def cluster_meta = meta + [cluster_id: cluster_id.toInteger()]

            [cluster_meta, cluster_file]
        }

    //
    // STEP 5: Per-cluster assembly and polishing
    //
    PER_CLUSTER_ASSEMBLY(
        ch_per_cluster_reads,
        params.genome_size,
        params.polishing_reads,
        params.racon_rounds,
        params.medaka_model,
        params.skip_racon
    )
    ch_versions = ch_versions.mix(PER_CLUSTER_ASSEMBLY.out.versions)

    //
    // STEP 6: Classification
    //
    CLASSIFY_CLUSTERS(
        PER_CLUSTER_ASSEMBLY.out.consensus,
        VALIDATE_DATABASES.out.kraken2_db,
        VALIDATE_DATABASES.out.blast_db,
        VALIDATE_DATABASES.out.blast_tax_db,
        params.use_probabilistic_classification
    )
    ch_versions = ch_versions.mix(CLASSIFY_CLUSTERS.out.versions)

    //
    // CRITICAL: Aggregate per-cluster results back to sample level
    //
    // Group consensus sequences by sample
    ch_sample_consensus = PER_CLUSTER_ASSEMBLY.out.consensus
        .map { meta, consensus ->
            // Extract sample-level meta (remove cluster_id)
            def sample_meta = meta.findAll { key, value -> key != 'cluster_id' }
            def sample_id = meta.id

            [sample_id, meta.cluster_id, sample_meta, consensus]
        }
        .groupTuple(by: 0)  // Group by sample_id
        .map { sample_id, cluster_ids, sample_metas, consensus_files ->
            // Sort by cluster_id to maintain order
            def sorted = [cluster_ids, consensus_files].transpose().sort { it[0] }

            [sample_metas[0], sorted.collect { it[1] }]  // [meta, [consensus files]]
        }

    // Group classification results by sample
    ch_sample_classifications = CLASSIFY_CLUSTERS.out.json
        .map { meta, classification ->
            def sample_meta = meta.findAll { key, value -> key != 'cluster_id' }
            def sample_id = meta.id

            [sample_id, meta.cluster_id, sample_meta, classification]
        }
        .groupTuple(by: 0)
        .map { sample_id, cluster_ids, sample_metas, class_files ->
            def sorted = [cluster_ids, class_files].transpose().sort { it[0] }

            [sample_metas[0], sorted.collect { it[1] }]
        }

    //
    // STEP 7: Join all consensus sequences with annotations
    //
    // Handle optional classification: create dummy channel if classification is disabled
    // This ensures JOINCONSENSUS can run even without classification databases
    def classification_enabled = params.enable_kraken2 || params.enable_blast

    ch_sample_classifications_final = classification_enabled ?
        ch_sample_classifications :
        ch_sample_consensus.map { meta, consensus_files ->
            // Create dummy "NO_FILE" entries to match consensus structure
            def dummy_files = consensus_files.collect { file('NO_FILE') }
            [meta, dummy_files]
        }

    ch_joinconsensus_input = ch_sample_consensus
        .join(ch_sample_classifications_final, by: 0)

    JOINCONSENSUS(
        ch_joinconsensus_input
    )
    ch_versions = ch_versions.mix(JOINCONSENSUS.out.versions.first())

    //
    // STEP 7b: Extract potentially novel sequences (optional)
    //
    // Only run if probabilistic classification is enabled and we have classification results
    if (params.use_probabilistic_classification && classification_enabled) {
        // First, aggregate individual classification JSON files into single array
        AGGREGATE_CLASSIFICATIONS(
            ch_sample_classifications
        )
        ch_versions = ch_versions.mix(AGGREGATE_CLASSIFICATIONS.out.versions.first())

        // Combine consensus FASTA with aggregated classification JSON
        ch_extract_novel_input = JOINCONSENSUS.out.fasta
            .join(AGGREGATE_CLASSIFICATIONS.out.aggregated, by: 0)

        // Extract sequences with low confidence or marked as novel
        EXTRACT_NOVEL_SEQUENCES(
            ch_extract_novel_input,
            params.novelty_threshold
        )
        ch_versions = ch_versions.mix(EXTRACT_NOVEL_SEQUENCES.out.versions.first())
    }

    //
    // STEP 8: Calculate abundances and diversity metrics
    //
    ch_getabundances_input = SPLITCLUSTERS.out.stats
        .join(ch_sample_classifications_final, by: 0)

    GETABUNDANCES(
        ch_getabundances_input
    )
    ch_versions = ch_versions.mix(GETABUNDANCES.out.versions.first())

    //
    // STEP 9: Create comprehensive plots
    //
    ch_plotresults_input = ch_embedding_coords
        .join(HDBSCAN.out.clusters, by: 0)
        .join(GETABUNDANCES.out.abundances, by: 0)
        .join(JOINCONSENSUS.out.annotations, by: 0)

    PLOTRESULTS(
        ch_plotresults_input
    )
    ch_versions = ch_versions.mix(PLOTRESULTS.out.versions.first())

    //
    // STEP 10: Build phylogenetic tree (optional)
    //
    // Phylogenetic tree construction for evolutionary analysis
    // Uses MAFFT for multiple sequence alignment + FastTree for tree building
    //
    if (params.build_phylotree) {
        BUILD_PHYLOTREE(
            JOINCONSENSUS.out.fasta,
            params.phylotree_alignment_method
        )
        ch_versions = ch_versions.mix(BUILD_PHYLOTREE.out.versions.first())

        //
        // STEP 11: Create phyloseq object (optional, requires phylotree)
        //
        // Combines phylogenetic tree, abundance table, and taxonomy into phyloseq object
        // Enables advanced diversity analysis in R (Faith's PD, UniFrac, etc.)
        //
        if (params.create_phyloseq) {
            ch_phyloseq_input = BUILD_PHYLOTREE.out.tree
                .join(GETABUNDANCES.out.abundances, by: 0)
                .join(JOINCONSENSUS.out.annotations, by: 0)

            CREATE_PHYLOSEQ(
                ch_phyloseq_input,
                params.calculate_phylo_diversity
            )
            ch_versions = ch_versions.mix(CREATE_PHYLOSEQ.out.versions.first())
        }
    }

    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_pipeline_software_mqc_versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }

    //
    // MODULE: MultiQC
    //
    if (params.multiqc) {
        ch_multiqc_config        = Channel.fromPath(
            "$projectDir/assets/multiqc_config.yml", checkIfExists: true
        )
        ch_multiqc_custom_config = params.multiqc_config ?
            Channel.fromPath(params.multiqc_config, checkIfExists: true) :
            Channel.empty()
        ch_multiqc_logo          = params.multiqc_logo ?
            Channel.fromPath(params.multiqc_logo, checkIfExists: true) :
            Channel.empty()

        summary_params      = paramsSummaryMap(
            workflow, parameters_schema: "nextflow_schema.json"
        )
        ch_workflow_summary = Channel.value(paramsSummaryMultiqc(summary_params))
        ch_multiqc_files = ch_multiqc_files.mix(
            ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml')
        )
        ch_multiqc_custom_methods_description = params.multiqc_methods_description ?
            file(params.multiqc_methods_description, checkIfExists: true) :
            file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
        ch_methods_description                = Channel.value(
            methodsDescriptionText(ch_multiqc_custom_methods_description)
        )

        ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
        ch_multiqc_files = ch_multiqc_files.mix(
            ch_methods_description.collectFile(
                name: 'methods_description_mqc.yaml',
                sort: true
            )
        )

        MULTIQC(
            ch_multiqc_files.collect(),
            ch_multiqc_config.toList(),
            ch_multiqc_custom_config.toList(),
            ch_multiqc_logo.toList()
        )

        multiqc_report = MULTIQC.out.report.toList()
    } else {
        multiqc_report = Channel.empty()
    }

    emit:
    consensus         = JOINCONSENSUS.out.fasta        // channel: [ meta, fasta ]
    annotations       = JOINCONSENSUS.out.annotations  // channel: [ meta, tsv ]
    abundances        = GETABUNDANCES.out.abundances   // channel: [ meta, csv ]
    diversity         = GETABUNDANCES.out.diversity    // channel: [ meta, txt ]
    plots             = PLOTRESULTS.out.plots          // channel: [ meta, png ]
    html_report       = PLOTRESULTS.out.html           // channel: [ meta, html ]
    multiqc_report    = multiqc_report                 // channel: [ html ]
    versions          = ch_versions                    // channel: [ yml ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
