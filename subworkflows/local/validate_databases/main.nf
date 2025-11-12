#!/usr/bin/env nextflow

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    VALIDATE AND PREPARE CLASSIFICATION DATABASES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow VALIDATE_DATABASES {

    main:
    ch_versions = Channel.empty()

    // Validate KRAKEN2 database
    if (params.kraken2_db) {
        ch_kraken2_db = Channel
            .fromPath(params.kraken2_db, checkIfExists: true, type: 'dir')
            .map { db ->
                // Check for required KRAKEN2 files
                def hash_file = file("${db}/hash.k2d")
                def opts_file = file("${db}/opts.k2d")
                def taxo_file = file("${db}/taxo.k2d")

                if (!hash_file.exists() || !opts_file.exists() || !taxo_file.exists()) {
                    error """
                    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    ERROR: Invalid KRAKEN2 database
                    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                    Database path: ${db}

                    Missing required files:
                    ${!hash_file.exists() ? "  ✗ hash.k2d" : ""}
                    ${!opts_file.exists() ? "  ✗ opts.k2d" : ""}
                    ${!taxo_file.exists() ? "  ✗ taxo.k2d" : ""}

                    Please ensure you have a complete KRAKEN2 database.
                    Download: https://benlangmead.github.io/aws-indexes/k2
                    """.stripIndent()
                }

                log.info "✓ KRAKEN2 database validated: ${db}"
                return db
            }
    } else {
        if (params.enable_kraken2) {
            log.warn """
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            WARNING: KRAKEN2 enabled but no database provided
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

            KRAKEN2 classification will be SKIPPED.

            To enable KRAKEN2:
              --kraken2_db /path/to/kraken2/database
            """.stripIndent()
        }
        ch_kraken2_db = Channel.empty()
    }

    // Validate BLAST database
    if (params.blast_db) {
        ch_blast_db = Channel
            .fromPath("${params.blast_db}*", checkIfExists: false)
            .collect()
            .map { files ->
                def db_path = params.blast_db
                def db_name = file(db_path).name

                // Check for required BLAST database files (.nhr, .nin, .nsq)
                def required_exts = ['.nhr', '.nin', '.nsq']
                def found_exts = required_exts.findAll { ext ->
                    file("${db_path}${ext}").exists()
                }

                if (found_exts.size() != required_exts.size()) {
                    error """
                    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    ERROR: Invalid BLAST database
                    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                    Database: ${db_path}

                    Missing required files:
                    ${required_exts.collect { ext ->
                        def exists = file("${db_path}${ext}").exists()
                        exists ? "  ✓ ${db_name}${ext}" : "  ✗ ${db_name}${ext}"
                    }.join('\n')}

                    Please ensure you have a formatted BLAST database.
                    See: https://www.ncbi.nlm.nih.gov/books/NBK279688/
                    """.stripIndent()
                }

                log.info "✓ BLAST database validated: ${db_path}"
                return file(db_path).parent
            }

        // Validate taxonomy database
        if (params.blast_taxdb) {
            ch_tax_db = Channel
                .fromPath("${params.blast_taxdb}/*.dmp", checkIfExists: false)
                .collect()
                .map { files ->
                    def has_names = file("${params.blast_taxdb}/names.dmp").exists()
                    def has_nodes = file("${params.blast_taxdb}/nodes.dmp").exists()

                    if (!has_names || !has_nodes) {
                        error """
                        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                        ERROR: Invalid BLAST taxonomy database
                        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                        Taxonomy DB: ${params.blast_taxdb}

                        Missing required files:
                        ${has_names ? "  ✓ names.dmp" : "  ✗ names.dmp"}
                        ${has_nodes ? "  ✓ nodes.dmp" : "  ✗ nodes.dmp"}

                        Download: update_blastdb.pl --decompress taxdb
                        """.stripIndent()
                    }

                    log.info "✓ BLAST taxonomy database validated: ${params.blast_taxdb}"
                    return file(params.blast_taxdb)
                }
        } else {
            log.warn "BLAST taxonomy database not provided - taxon names may not be resolved"
            ch_tax_db = Channel.empty()
        }
    } else {
        if (params.enable_blast) {
            log.warn """
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            WARNING: BLAST enabled but no database provided
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

            BLAST classification will be SKIPPED.

            To enable BLAST:
              --blast_db /path/to/blast/database
              --blast_taxdb /path/to/taxdb (optional)
            """.stripIndent()
        }
        ch_blast_db = Channel.empty()
        ch_tax_db = Channel.empty()
    }

    // Validate FastANI reference genomes
    if (params.fastani_ref_dir) {
        ch_fastani_refs = Channel
            .fromPath(params.fastani_ref_dir, checkIfExists: true, type: 'dir')
            .map { ref_dir ->
                // Count reference genomes
                def ref_files = file("${ref_dir}/*.{fasta,fa,fna}", type: 'file')
                def n_refs = ref_files instanceof List ? ref_files.size() : (ref_files ? 1 : 0)

                if (n_refs == 0) {
                    error """
                    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    ERROR: No FastANI reference genomes found
                    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                    Reference directory: ${ref_dir}

                    No FASTA files found (.fasta, .fa, .fna)

                    Please provide a directory with reference genomes.
                    """.stripIndent()
                }

                log.info "✓ FastANI references validated: ${n_refs} genomes in ${ref_dir}"
                return ref_dir
            }
    } else {
        if (params.enable_fastani) {
            log.warn """
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            WARNING: FastANI enabled but no references provided
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

            FastANI classification will be SKIPPED.

            To enable FastANI:
              --fastani_ref_dir /path/to/reference/genomes
            """.stripIndent()
        }
        ch_fastani_refs = Channel.empty()
    }

    emit:
    kraken2_db   = ch_kraken2_db
    blast_db     = ch_blast_db
    blast_tax_db = ch_tax_db
    fastani_refs = ch_fastani_refs
    versions     = ch_versions
}
