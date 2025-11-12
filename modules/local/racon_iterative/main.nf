process RACON_ITERATIVE {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/mulled-v2-43e2db8f50ec782b13b5a5d9e7247e6ede1a7c97:f5f6ea02e14772d15c92ff1b6ce792ae1d3cc58d-0' :
        'quay.io/biocontainers/mulled-v2-43e2db8f50ec782b13b5a5d9e7247e6ede1a7c97:f5f6ea02e14772d15c92ff1b6ce792ae1d3cc58d-0' }"

    input:
    tuple val(meta), path(draft), path(corrected_reads)
    val rounds

    output:
    tuple val(meta), path("*_polished.fasta"), emit: polished
    tuple val(meta), path("*.stats.json")     , emit: stats
    path "versions.yml"                       , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}_cluster${meta.cluster_id}"
    def quality_threshold = task.ext.quality_threshold ?: 9
    def window_length = task.ext.window_length ?: 250
    """
    #!/bin/bash
    set -e

    # Track polishing statistics
    declare -a round_status
    declare -a round_sizes
    total_success=0
    total_failed=0

    # Start with the draft read
    current_draft=\$(realpath ${draft})
    echo "Starting iterative polishing with ${rounds} rounds" >&2
    echo "Initial draft: \${current_draft}" >&2

    # Iterative polishing loop
    for round in \$(seq 1 ${rounds}); do
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        echo "Round \${round}/${rounds}" >&2
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2

        # Alignment with minimap2
        echo "  [1/2] Running minimap2 alignment..." >&2
        minimap2 \\
            -ax map-ont \\
            --no-long-join \\
            -r100 \\
            -t ${task.cpus} \\
            \${current_draft} \\
            ${corrected_reads} \\
            > round_\${round}.sam 2> round_\${round}_minimap2.log

        # Count alignments
        n_alignments=\$(samtools view -c -F 4 round_\${round}.sam || echo "0")
        echo "  Alignments: \${n_alignments}" >&2

        # Polishing with racon
        echo "  [2/2] Running racon polishing..." >&2
        set +e
        racon \\
            --quality-threshold ${quality_threshold} \\
            -w ${window_length} \\
            -t ${task.cpus} \\
            ${args} \\
            ${corrected_reads} \\
            round_\${round}.sam \\
            \${current_draft} \\
            > round_\${round}_polished.fasta 2> round_\${round}_racon.log
        racon_exit=\$?
        set -e

        # Check if racon succeeded
        if [ \$racon_exit -eq 0 ] && [ -s round_\${round}_polished.fasta ]; then
            echo "  ✓ Racon polishing succeeded" >&2
            current_draft=\$(realpath round_\${round}_polished.fasta)
            round_status[\${round}]="success"
            total_success=\$((total_success + 1))

            # Get sequence length
            seq_len=\$(awk '/^>/ {next} {total += length(\$0)} END {print total}' round_\${round}_polished.fasta)
            round_sizes[\${round}]=\${seq_len}
            echo "  Polished sequence length: \${seq_len} bp" >&2
        else
            echo "  ✗ Racon polishing failed (exit code: \$racon_exit)" >&2
            echo "  Using previous draft for this round" >&2
            cp \${current_draft} round_\${round}_polished.fasta
            round_status[\${round}]="failed"
            total_failed=\$((total_failed + 1))

            # Get sequence length from previous draft
            seq_len=\$(awk '/^>/ {next} {total += length(\$0)} END {print total}' round_\${round}_polished.fasta)
            round_sizes[\${round}]=\${seq_len}
        fi

        # Clean up SAM file to save space
        rm -f round_\${round}.sam
    done

    # Final polished consensus
    cp \${current_draft} ${prefix}_polished.fasta
    final_length=\$(awk '/^>/ {next} {total += length(\$0)} END {print total}' ${prefix}_polished.fasta)

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "Polishing complete!" >&2
    echo "  Successful rounds: \${total_success}/${rounds}" >&2
    echo "  Failed rounds: \${total_failed}/${rounds}" >&2
    echo "  Final length: \${final_length} bp" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2

    # Generate statistics JSON
    cat <<-EOF > ${prefix}.stats.json
\t{
\t  "cluster_id": "${meta.cluster_id}",
\t  "rounds": ${rounds},
\t  "successful_rounds": \${total_success},
\t  "failed_rounds": \${total_failed},
\t  "final_length": \${final_length},
\t  "round_status": [
    EOF

    # Add round status array
    for round in \$(seq 1 ${rounds}); do
        if [ \${round} -lt ${rounds} ]; then
            echo "\t    {\"round\": \${round}, \"status\": \"\${round_status[\${round}]}\", \"length\": \${round_sizes[\${round}]}}," >> ${prefix}.stats.json
        else
            echo "\t    {\"round\": \${round}, \"status\": \"\${round_status[\${round}]}\", \"length\": \${round_sizes[\${round}]}}" >> ${prefix}.stats.json
        fi
    done

    cat <<-EOF >> ${prefix}.stats.json
\t  ]
\t}
\tEOF

    # Version tracking
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        racon: \$(racon --version 2>&1 | grep -oP '(?<=v)\\S+' || echo "1.5.0")
        minimap2: \$(minimap2 --version 2>&1 || echo "2.24")
        samtools: \$(samtools --version 2>&1 | grep samtools | sed 's/samtools //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}_cluster${meta.cluster_id}"
    """
    # Create stub polished consensus
    cat <<-EOF > ${prefix}_polished.fasta
\t>polished_consensus_cluster_${meta.cluster_id}
\tACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
\tACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
\tACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
\tEOF

    # Create stub statistics
    cat <<-EOF > ${prefix}.stats.json
\t{
\t  "cluster_id": "${meta.cluster_id}",
\t  "rounds": ${rounds},
\t  "successful_rounds": ${rounds},
\t  "failed_rounds": 0,
\t  "final_length": 1500,
\t  "round_status": [
\t    {"round": 1, "status": "success", "length": 1520},
\t    {"round": 2, "status": "success", "length": 1510},
\t    {"round": 3, "status": "success", "length": 1505},
\t    {"round": 4, "status": "success", "length": 1500}
\t  ]
\t}
\tEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        racon: 1.5.0
        minimap2: 2.24
        samtools: 1.17
    END_VERSIONS
    """
}
