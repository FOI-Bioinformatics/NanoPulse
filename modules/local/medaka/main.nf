process MEDAKA {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/medaka:1.11.3--py310hdcf5f25_0' :
        'quay.io/biocontainers/medaka:1.11.3--py310hdcf5f25_0' }"

    input:
    tuple val(meta), path(draft), path(corrected_reads)
    val model

    output:
    tuple val(meta), path("*_consensus.fasta"), emit: consensus
    tuple val(meta), path("*.stats.json")      , emit: stats
    path "versions.yml"                        , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}_cluster${meta.cluster_id}"
    def medaka_model = model ?: 'r941_min_high_g303'
    """
    #!/bin/bash
    set +e

    echo "Running Medaka consensus polishing..." >&2
    echo "  Model: ${medaka_model}" >&2
    echo "  Draft: ${draft}" >&2
    echo "  Reads: ${corrected_reads}" >&2

    # Run medaka_consensus
    medaka_consensus \\
        -i ${corrected_reads} \\
        -d ${draft} \\
        -o medaka_output \\
        -t ${task.cpus} \\
        -m ${medaka_model} \\
        ${args} \\
        > medaka.log 2>&1
    medaka_exit=\$?

    # Check if medaka succeeded
    if [ \$medaka_exit -eq 0 ] && [ -f medaka_output/consensus.fasta ]; then
        echo "+ Medaka polishing succeeded" >&2

        # Extract consensus
        cp medaka_output/consensus.fasta ${prefix}_consensus.fasta

        # Get sequence statistics
        n_sequences=\$(grep -c "^>" ${prefix}_consensus.fasta || echo "0")
        total_length=\$(awk '/^>/ {next} {total += length(\$0)} END {print total}' ${prefix}_consensus.fasta)

        # Generate statistics
        cat <<-EOF > ${prefix}.stats.json
\t{
\t  "success": true,
\t  "cluster_id": "${meta.cluster_id}",
\t  "model": "${medaka_model}",
\t  "n_sequences": \${n_sequences},
\t  "total_length": \${total_length},
\t  "exit_code": \$medaka_exit,
\t  "method": "medaka"
\t}
\tEOF

        echo "  Consensus sequences: \${n_sequences}" >&2
        echo "  Total length: \${total_length} bp" >&2
    else
        # Medaka failed - use draft as fallback
        echo "X Medaka polishing failed (exit code: \$medaka_exit)" >&2
        echo "  Using draft sequence as consensus (fallback)" >&2

        # Create output directory if it doesn't exist
        mkdir -p medaka_output

        # Copy draft to consensus output
        cp ${draft} ${prefix}_consensus.fasta

        # Get sequence statistics from draft
        n_sequences=\$(grep -c "^>" ${prefix}_consensus.fasta || echo "0")
        total_length=\$(awk '/^>/ {next} {total += length(\$0)} END {print total}' ${prefix}_consensus.fasta)

        # Generate failure statistics
        cat <<-EOF > ${prefix}.stats.json
\t{
\t  "success": false,
\t  "cluster_id": "${meta.cluster_id}",
\t  "model": "${medaka_model}",
\t  "n_sequences": \${n_sequences},
\t  "total_length": \${total_length},
\t  "exit_code": \$medaka_exit,
\t  "method": "fallback_draft",
\t  "warning": "Medaka failed, using draft sequence"
\t}
\tEOF

        echo "  WARNING: Using unpolished draft (length: \${total_length} bp)" >&2
    fi

    # Version tracking
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        medaka: \$(medaka --version 2>&1 | sed 's/medaka //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}_cluster${meta.cluster_id}"
    """
    # Create stub consensus
    cat <<-EOF > ${prefix}_consensus.fasta
\t>consensus_cluster_${meta.cluster_id}
\tACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
\tACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
\tACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
\tACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
\tEOF

    # Create stub statistics
    cat <<-EOF > ${prefix}.stats.json
\t{
\t  "success": true,
\t  "cluster_id": "${meta.cluster_id}",
\t  "model": "${model ?: 'r941_min_high_g303'}",
\t  "n_sequences": 1,
\t  "total_length": 1600,
\t  "exit_code": 0,
\t  "method": "medaka"
\t}
\tEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        medaka: 1.7.2
    END_VERSIONS
    """
}
