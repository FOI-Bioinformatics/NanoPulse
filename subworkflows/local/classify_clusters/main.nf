#!/usr/bin/env nextflow

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// NOTE: nf-core modules need to be installed separately:
//   nf-core modules install kraken2/kraken2
//   nf-core modules install blast/blastn
//
// Once installed, uncomment the following lines:
// include { KRAKEN2_KRAKEN2 } from '../../../modules/nf-core/kraken2/kraken2/main'
// include { BLAST_BLASTN    } from '../../../modules/nf-core/blast/blastn/main'

include { FASTANI_CLASSIFY   } from '../../../modules/local/fastani_classify/main'
include { CLASSIFY_CONSENSUS } from '../../../modules/local/classify_consensus/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW: CLASSIFY_CLUSTERS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    Description:
        Taxonomic classification of consensus sequences using multiple classifiers:
        - KRAKEN2: k-mer based classification
        - BLAST: alignment-based classification
        - FastANI: ANI-based classification
        All results are combined into consensus classification.

    Input:
        consensus: Channel of [meta, consensus.fasta] from assembly
        kraken2_db: KRAKEN2 database path
        blast_db: BLAST database path
        blast_tax_db: BLAST taxonomy database path
        fastani_refs: FastANI reference genomes path

    Output:
        classification: Final classification CSV
        json: Classification results in JSON format
        combined: Human-readable combined results
        individual results from each classifier
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow CLASSIFY_CLUSTERS {

    take:
    consensus        // channel: [val(meta), path(consensus.fasta)]
    kraken2_db       // channel: path to kraken2 database
    blast_db         // channel: path to blast database
    blast_tax_db     // channel: path to blast taxonomy database
    fastani_refs     // channel: path to FastANI reference genomes

    main:

    ch_versions = Channel.empty()
    ch_classifications = Channel.empty()

    // Branch consensus based on file size
    consensus
        .branch { meta, fasta ->
            valid: fasta.size() > 0
            empty: true
        }
        .set { ch_consensus_branched }

    //
    // Run KRAKEN2 if enabled and database provided
    //
    // NOTE: Uncomment when nf-core module is installed
    /*
    if (params.enable_kraken2) {
        KRAKEN2_KRAKEN2(
            ch_consensus_branched.valid,
            kraken2_db,
            false,  // save_output_fastqs
            false   // save_reads_assignment
        )

        ch_classifications = ch_classifications.mix(
            KRAKEN2_KRAKEN2.out.report
                .map { meta, report ->
                    [meta, 'kraken2', report]
                }
        )

        ch_versions = ch_versions.mix(KRAKEN2_KRAKEN2.out.versions.first())
    }
    */

    //
    // Run BLAST if enabled and database provided
    //
    // NOTE: Uncomment when nf-core module is installed
    /*
    if (params.enable_blast) {
        // Prepare BLAST input with database
        ch_blast_input = ch_consensus_branched.valid
            .combine(blast_db)

        BLAST_BLASTN(
            ch_blast_input
        )

        ch_classifications = ch_classifications.mix(
            BLAST_BLASTN.out.txt
                .map { meta, results ->
                    [meta, 'blast', results]
                }
        )

        ch_versions = ch_versions.mix(BLAST_BLASTN.out.versions.first())
    }
    */

    //
    // Run FastANI if enabled and references provided
    //
    if (params.enable_fastani) {
        FASTANI_CLASSIFY(
            ch_consensus_branched.valid,
            fastani_refs
        )

        ch_classifications = ch_classifications.mix(
            FASTANI_CLASSIFY.out.results
                .map { meta, results ->
                    [meta, 'fastani', results]
                }
        )

        ch_versions = ch_versions.mix(FASTANI_CLASSIFY.out.versions.first())
    }

    //
    // Group classifications by meta and combine
    //
    ch_classifications
        .groupTuple(by: 0)
        .map { meta, sources, files ->
            // Flatten sources and files if needed
            def sources_flat = sources.flatten()
            def files_flat = files.flatten()
            [meta, sources_flat, files_flat]
        }
        .set { ch_grouped_classifications }

    //
    // Combine all classification results
    //
    ch_grouped_classifications
        .filter { meta, sources, files ->
            // Only process if we have at least one classification result
            sources.size() > 0
        }
        .set { ch_valid_classifications }

    // Run classification if we have any valid classifications
    CLASSIFY_CONSENSUS(ch_valid_classifications)

    ch_versions = ch_versions.mix(CLASSIFY_CONSENSUS.out.versions.first().ifEmpty([]))

    emit:
    classification = params.enable_kraken2 || params.enable_blast || params.enable_fastani ?
                     CLASSIFY_CONSENSUS.out.classification : Channel.empty()
    json          = params.enable_kraken2 || params.enable_blast || params.enable_fastani ?
                    CLASSIFY_CONSENSUS.out.json : Channel.empty()
    combined      = params.enable_kraken2 || params.enable_blast || params.enable_fastani ?
                    CLASSIFY_CONSENSUS.out.combined : Channel.empty()
    // Individual classifier outputs
    // kraken2       = params.enable_kraken2 ? KRAKEN2_KRAKEN2.out.report : Channel.empty()
    // blast         = params.enable_blast ? BLAST_BLASTN.out.txt : Channel.empty()
    fastani       = params.enable_fastani ? FASTANI_CLASSIFY.out.results : Channel.empty()
    versions      = ch_versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOW INTROSPECTION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow.onComplete {
    if (params.enable_kraken2 || params.enable_blast || params.enable_fastani) {
        log.info """
        ====================================================================
        Classification Subworkflow Complete!
        ====================================================================
        """.stripIndent()
    }
}
