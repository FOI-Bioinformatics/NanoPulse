#!/usr/bin/env nextflow

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { RAVEN_CORRECT   } from '../../../modules/local/raven_correct/main'
include { DRAFT_SELECTION } from '../../../modules/local/draft_selection/main'
include { RACON_ITERATIVE } from '../../../modules/local/racon_iterative/main'
include { MEDAKA          } from '../../../modules/local/medaka/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW: PER_CLUSTER_ASSEMBLY
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    Description:
        Performs consensus sequence generation for each cluster through:
        1. Raven assembly with built-in polishing
        2. Draft selection via fastANI
        3. Iterative Racon polishing (optional)
        4. Medaka neural network polishing

    Input:
        ch_cluster_reads: Channel of [meta, reads] tuples (one per cluster)
        genome_size: Expected genome/amplicon size (e.g., "1.5k")
        polishing_reads: Number of reads to use for correction
        racon_rounds: Number of Racon polishing rounds (default: 4)
        medaka_model: Medaka basecalling model (e.g., "r941_min_high_g303")

    Output:
        consensus: Channel of [meta, consensus.fasta] - final polished sequences
        stats: Channel of statistics from all steps
        versions: Software versions
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PER_CLUSTER_ASSEMBLY {

    take:
    ch_cluster_reads    // channel: [val(meta), path(reads)]
    genome_size         // val: genome size (e.g., "1.5k")
    polishing_reads     // val: number of reads for correction (default: 100)
    racon_rounds        // val: number of racon rounds (default: 4)
    medaka_model        // val: medaka model (default: "r941_min_high_g303")
    skip_racon          // val: skip Racon polishing (default: false)

    main:

    ch_versions = Channel.empty()
    ch_all_stats = Channel.empty()

    //
    // MODULE: RAVEN_CORRECT - Assemble and correct reads using Raven
    //
    RAVEN_CORRECT(
        ch_cluster_reads,
        genome_size,
        polishing_reads
    )
    ch_versions = ch_versions.mix(RAVEN_CORRECT.out.versions.first())
    ch_all_stats = ch_all_stats.mix(RAVEN_CORRECT.out.stats)

    //
    // Filter successful assemblies
    // Raven can fail for small clusters - this is expected
    //
    ch_corrected_reads = RAVEN_CORRECT.out.corrected
        .filter { meta, fasta ->
            if (fasta.size() > 0) {
                return true
            } else {
                log.warn "Cluster ${meta.cluster_id} failed Raven assembly - skipping polishing"
                return false
            }
        }

    //
    // MODULE: DRAFT_SELECTION - Select best read as draft using fastANI
    //
    DRAFT_SELECTION(
        ch_corrected_reads
    )
    ch_versions = ch_versions.mix(DRAFT_SELECTION.out.versions.first())
    ch_all_stats = ch_all_stats.mix(DRAFT_SELECTION.out.stats)

    //
    // Join draft with corrected reads for polishing
    // Need both draft and reads for Racon/Medaka
    //
    ch_draft_and_reads = DRAFT_SELECTION.out.draft
        .join(ch_corrected_reads, by: 0)  // Join on meta
        .map { meta, draft, corrected_reads ->
            [meta, draft, corrected_reads]
        }

    //
    // Conditional: Skip Racon if requested (60-80% faster)
    // Recent benchmarks show Medaka-only achieves same accuracy as Racon+Medaka
    //
    if (!skip_racon) {
        //
        // MODULE: RACON_ITERATIVE - Iterative polishing with Racon
        //
        log.info "Running Racon polishing (${racon_rounds} rounds)"
        RACON_ITERATIVE(
            ch_draft_and_reads,
            racon_rounds
        )
        ch_versions = ch_versions.mix(RACON_ITERATIVE.out.versions.first())
        ch_all_stats = ch_all_stats.mix(RACON_ITERATIVE.out.stats)

        //
        // Join polished consensus with corrected reads for Medaka
        //
        ch_polished_and_reads = RACON_ITERATIVE.out.polished
            .join(ch_corrected_reads, by: 0)  // Join on meta
            .map { meta, polished, corrected_reads ->
                [meta, polished, corrected_reads]
            }
    } else {
        //
        // Skip Racon - use draft directly for Medaka
        //
        log.info "Skipping Racon polishing (skip_racon=true) - using draft for Medaka"
        ch_polished_and_reads = ch_draft_and_reads
    }

    //
    // MODULE: MEDAKA - Neural network polishing
    //
    MEDAKA(
        ch_polished_and_reads,
        medaka_model
    )
    ch_versions = ch_versions.mix(MEDAKA.out.versions.first())
    ch_all_stats = ch_all_stats.mix(MEDAKA.out.stats)

    emit:
    consensus = MEDAKA.out.consensus           // channel: [val(meta), path(consensus)]
    stats     = ch_all_stats                   // channel: [val(meta), path(stats.json)]
    versions  = ch_versions                    // channel: path(versions.yml)
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOW INTROSPECTION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow.onComplete {
    log.info """
    ====================================================================
    Per-cluster Assembly Subworkflow Complete!
    ====================================================================
    """.stripIndent()
}
