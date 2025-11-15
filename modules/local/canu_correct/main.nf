process CANU_CORRECT {
    tag "$meta.id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/canu:2.2--ha47f30e_0' :
        'quay.io/biocontainers/canu:2.2--ha47f30e_0' }"

    input:
    tuple val(meta), path(reads)
    val genome_size
    val polishing_reads

    output:
    tuple val(meta), path("*.correctedReads.fasta"), emit: corrected, optional: true
    tuple val(meta), path("*.stats.json")           , emit: stats
    path "versions.yml"                             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}_cluster${meta.cluster_id}"
    def random_seed = task.ext.random_seed ?: 42
    """
    # Subset reads for polishing (default: first 100 reads)
    head -n\$(( ${polishing_reads} * 4 )) ${reads} > subset.fastq

    # Count input reads for statistics
    INPUT_READS=\$(( \$(wc -l < subset.fastq) / 4 ))

    # Run Canu correction
    # Exit code 0 = success, 1 = failure (expected for small clusters)
    set +e
    canu \\
        -correct \\
        -p ${prefix} \\
        -nanopore-raw subset.fastq \\
        genomeSize=${genome_size} \\
        stopOnLowCoverage=1 \\
        minInputCoverage=2 \\
        minReadLength=500 \\
        minOverlapLength=200 \\
        useGrid=false \\
        -seed ${random_seed} \\
        ${args}
    CANU_EXIT=\$?
    set -e

    # Check if correction succeeded
    if [ \$CANU_EXIT -eq 0 ] && [ -f ${prefix}.correctedReads.fasta.gz ]; then
        # Decompress output
        gunzip ${prefix}.correctedReads.fasta.gz

        # Count corrected reads
        CORRECTED_READS=\$(grep -c "^>" ${prefix}.correctedReads.fasta || echo "0")

        # Generate statistics
        cat <<-EOF > ${prefix}.stats.json
\t{
\t  "success": true,
\t  "input_reads": \$INPUT_READS,
\t  "corrected_reads": \$CORRECTED_READS,
\t  "correction_rate": \$(echo "scale=4; \$CORRECTED_READS / \$INPUT_READS" | bc),
\t  "cluster_id": "${meta.cluster_id}",
\t  "exit_code": \$CANU_EXIT
\t}
\tEOF

        echo "+ Canu correction succeeded: \$CORRECTED_READS reads corrected from \$INPUT_READS input" >&2
    else
        # Correction failed - this is expected for small clusters
        echo "WARNING: Canu correction failed for cluster ${meta.cluster_id} (exit code: \$CANU_EXIT)" >&2
        echo "This is expected for small clusters with insufficient coverage" >&2

        # Generate failure statistics
        cat <<-EOF > ${prefix}.stats.json
\t{
\t  "success": false,
\t  "input_reads": \$INPUT_READS,
\t  "corrected_reads": 0,
\t  "correction_rate": 0,
\t  "cluster_id": "${meta.cluster_id}",
\t  "exit_code": \$CANU_EXIT,
\t  "failure_reason": "Insufficient coverage or reads"
\t}
\tEOF
    fi

    # Version tracking
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        canu: \$(canu --version 2>&1 | grep -oP '(?<=Canu )\\S+' || echo "2.2")
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}_cluster${meta.cluster_id}"
    """
    # Create stub corrected reads
    cat <<-EOF > ${prefix}.correctedReads.fasta
\t>corrected_read_1
\tACGTACGTACGTACGTACGT
\t>corrected_read_2
\tTGCATGCATGCATGCATGCA
\tEOF

    # Create stub statistics
    cat <<-EOF > ${prefix}.stats.json
\t{
\t  "success": true,
\t  "input_reads": 100,
\t  "corrected_reads": 95,
\t  "correction_rate": 0.95,
\t  "cluster_id": "${meta.cluster_id}",
\t  "exit_code": 0
\t}
\tEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        canu: 2.2
    END_VERSIONS
    """
}
