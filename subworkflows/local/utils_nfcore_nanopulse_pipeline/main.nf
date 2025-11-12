//
// Subworkflow with utility functions specific to the NanoPulse pipeline
//

include { UTILS_NFCORE_PIPELINE } from '../../nf-core/utils_nfcore_pipeline'
include { paramsSummaryMap        } from 'plugin/nf-schema'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW: PIPELINE_INITIALISATION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_INITIALISATION {
    take:
    version              // boolean: Display version and exit
    help                 // boolean: Display help text
    validate_params      // boolean: Boolean whether to validate parameters against the schema at runtime
    monochrome_logs      // boolean: Do not use coloured log outputs
    nextflow_cli_args    // array: List of positional nextflow CLI args
    outdir               // string: The output directory where the results will be saved

    main:

    //
    // Print version and exit if required (not supported in nf-schema)
    //
    if (version) {
        def version_string = "NanoPulse v${workflow.manifest.version}"
        log.info version_string
        System.exit(0)
    }

    //
    // Print help message if required
    //
    if (help) {
        log.info"""
        NanoPulse - De novo clustering and consensus building for ONT 16S sequencing data

        Usage:
            nextflow run genomicsITER/nanopulse --input samplesheet.csv --outdir results -profile conda

        Mandatory arguments:
            --input       Path to comma-separated file containing information about the samples
            --outdir      The output directory where the results will be saved

        Optional arguments:
            -profile      Configuration profile to use (conda, docker, singularity)
        """.stripIndent()
        System.exit(0)
    }

    //
    // Validate parameters if required
    //
    if (validate_params) {
        // Add parameter validation if needed
    }

    //
    // Create channel from input file provided through params.input
    //
    ch_samplesheet = Channel.fromPath(params.input)
        .splitCsv(header: true)
        .map { row ->
            def meta = [id: row.sample, single_end: false]
            [meta, file(row.fastq, checkIfExists: true)]
        }

    emit:
    samplesheet = ch_samplesheet
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW: PIPELINE_COMPLETION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_COMPLETION {
    take:
    email                //  string: email address
    email_on_fail        //  string: email address sent on pipeline failure
    plaintext_email      // boolean: Send plain-text email instead of HTML
    outdir               //    path: Path to output directory where results will be published
    monochrome_logs      // boolean: Disable ANSI colour codes in log output
    hook_url             //  string: hook URL for notifications
    multiqc_report       //  string: Path to MultiQC report

    main:

    //
    // Completion summary is handled by workflow.onComplete in nextflow.config
    //
    log.info "Pipeline completed successfully!"
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// Generate methods description for MultiQC
//
def methodsDescriptionText(params) {
    def text = """
    <h2>Methods</h2>
    <h3>Data processing</h3>
    <p>NanoPulse was used for de novo clustering and consensus building of Oxford Nanopore 16S rRNA amplicon sequencing data.</p>
    """.stripIndent()

    return text
}
