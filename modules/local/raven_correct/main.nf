process RAVEN_CORRECT {
    tag "$meta.id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/raven-assembler:1.8.3--h8b12597_0' :
        'biocontainers/raven-assembler:1.8.3--h8b12597_0' }"

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
    def polishing_rounds = task.ext.polishing_rounds ?: 2
    """
    # Subset reads for assembly (using seqtk for efficiency)
    seqtk sample -s 42 ${reads} ${polishing_reads} > subset.fastq 2>/dev/null || \
        head -n\$(( ${polishing_reads} * 4 )) ${reads} > subset.fastq

    # Count input reads for statistics
    INPUT_READS=\$(( \$(wc -l < subset.fastq) / 4 ))

    # Run Raven assembly and error correction
    # Raven has built-in polishing (default: 2 rounds)
    # Exit code 0 = success, non-zero = failure (expected for small clusters)
    set +e
    raven \\
        --polishing-rounds ${polishing_rounds} \\
        --threads $task.cpus \\
        ${args} \\
        subset.fastq \\
        > ${prefix}.assembly.fasta \\
        2> raven.log
    RAVEN_EXIT=\$?
    set -e

    # Check if assembly succeeded
    if [ \$RAVEN_EXIT -eq 0 ] && [ -f ${prefix}.assembly.fasta ] && [ -s ${prefix}.assembly.fasta ]; then
        # Extract first contig as corrected reads (Raven produces consensus)
        # For amplicons, we typically get a single contig
        # Rename to match expected output format
        awk '/^>/ {if (seqlen) {print seq; seq=""; seqlen=0;} print; next} {seq=seq\$0; seqlen+=length(\$0)} END {if (seqlen) print seq}' \\
            ${prefix}.assembly.fasta > ${prefix}.correctedReads.fasta

        # Count corrected reads (actually contigs from Raven)
        CORRECTED_READS=\$(grep -c "^>" ${prefix}.correctedReads.fasta || echo "0")

        # Calculate assembly statistics
        TOTAL_LENGTH=\$(awk '/^>/ {next} {sum += length(\$0)} END {print sum}' ${prefix}.correctedReads.fasta || echo "0")
        AVG_LENGTH=\$(awk -v total=\$TOTAL_LENGTH -v count=\$CORRECTED_READS 'BEGIN {if (count > 0) print int(total/count); else print 0}')

        # Generate statistics
        cat <<-EOF > ${prefix}.stats.json
\t{
\t  "success": true,
\t  "input_reads": \$INPUT_READS,
\t  "output_contigs": \$CORRECTED_READS,
\t  "total_length": \$TOTAL_LENGTH,
\t  "average_contig_length": \$AVG_LENGTH,
\t  "cluster_id": "${meta.cluster_id}",
\t  "exit_code": \$RAVEN_EXIT,
\t  "assembler": "raven",
\t  "polishing_rounds": ${polishing_rounds}
\t}
\tEOF

        echo "+ Raven assembly succeeded: \$CORRECTED_READS contigs generated from \$INPUT_READS reads" >&2
        echo "+ Total assembly length: \$TOTAL_LENGTH bp (avg: \$AVG_LENGTH bp/contig)" >&2
    else
        # Assembly failed - this is expected for small clusters with insufficient coverage
        echo "WARNING: Raven assembly failed for cluster ${meta.cluster_id} (exit code: \$RAVEN_EXIT)" >&2
        echo "This is expected for small clusters with insufficient coverage" >&2

        # Show last 10 lines of log for debugging
        if [ -f raven.log ]; then
            echo "Last 10 lines of Raven log:" >&2
            tail -n 10 raven.log >&2
        fi

        # Generate failure statistics
        cat <<-EOF > ${prefix}.stats.json
\t{
\t  "success": false,
\t  "input_reads": \$INPUT_READS,
\t  "output_contigs": 0,
\t  "total_length": 0,
\t  "average_contig_length": 0,
\t  "cluster_id": "${meta.cluster_id}",
\t  "exit_code": \$RAVEN_EXIT,
\t  "failure_reason": "Insufficient coverage or reads for assembly",
\t  "assembler": "raven",
\t  "polishing_rounds": ${polishing_rounds}
\t}
\tEOF
    fi

    # Version tracking
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        raven: \$(raven --version 2>&1 | grep -oP 'v\\K[0-9.]+' || echo "1.8.3")
        seqtk: \$(seqtk 2>&1 | grep -oP 'Version: \\K[0-9.]+' || echo "1.3")
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}_cluster${meta.cluster_id}"
    """
    # Create stub corrected reads (assembly format)
    cat <<-EOF > ${prefix}.correctedReads.fasta
\t>contig_1 length=1500 coverage=50
\tACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
\tACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
\tEOF

    # Create stub statistics
    cat <<-EOF > ${prefix}.stats.json
\t{
\t  "success": true,
\t  "input_reads": 100,
\t  "output_contigs": 1,
\t  "total_length": 1500,
\t  "average_contig_length": 1500,
\t  "cluster_id": "${meta.cluster_id}",
\t  "exit_code": 0,
\t  "assembler": "raven",
\t  "polishing_rounds": 2
\t}
\tEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        raven: 1.8.3
        seqtk: 1.3
    END_VERSIONS
    """
}
