process FASTANI_CLASSIFY {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/fastani:1.34--h031d066_2' :
        'quay.io/biocontainers/fastani:1.34--h031d066_2' }"

    input:
    tuple val(meta), path(query)
    path(reference_genomes)

    output:
    tuple val(meta), path("*.ani.txt"), emit: results, optional: true
    tuple val(meta), path("*.stats.json"), emit: stats
    path "versions.yml"                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}_cluster${meta.cluster_id}"
    def min_ani = task.ext.min_ani ?: 80.0
    """
    #!/bin/bash
    set -e

    # Create reference list file
    # Handle both directory of references or single file list
    if [ -d "${reference_genomes}" ]; then
        find ${reference_genomes} -type f \\( -name "*.fasta" -o -name "*.fa" -o -name "*.fna" \\) > ref_list.txt
    elif [ -f "${reference_genomes}" ]; then
        # Assume it's already a list file
        cat ${reference_genomes} > ref_list.txt
    else
        echo "ERROR: reference_genomes must be directory or file list" >&2
        exit 1
    fi

    # Check if reference list is empty
    N_REFS=\$(wc -l < ref_list.txt)

    if [ \$N_REFS -eq 0 ]; then
        echo "ERROR: No reference genomes found" >&2

        # Create empty results
        touch ${prefix}.ani.txt

        cat <<-EOF > ${prefix}.stats.json
\t{
\t  "success": false,
\t  "cluster_id": "${meta.cluster_id}",
\t  "n_references": 0,
\t  "n_hits": 0,
\t  "best_ani": null,
\t  "best_reference": null,
\t  "error": "No reference genomes found"
\t}
\tEOF

        # Version tracking (must be created before early exit)
        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            fastani: \$(fastANI --version 2>&1 | grep -oP 'version \\K[0-9.]+' || echo "1.34")
        END_VERSIONS

        exit 0
    fi

    echo "Found \$N_REFS reference genomes" >&2

    # Run FastANI
    set +e
    fastANI \\
        -q ${query} \\
        --rl ref_list.txt \\
        -o ${prefix}.ani.txt \\
        -t ${task.cpus} \\
        ${args} \\
        2> fastani.log
    FASTANI_EXIT=\$?
    set -e

    # Check results
    if [ \$FASTANI_EXIT -eq 0 ] && [ -s ${prefix}.ani.txt ]; then
        echo "✓ FastANI completed successfully" >&2

        # Parse results - find best hit
        BEST_HIT=\$(sort -k3 -rn ${prefix}.ani.txt | head -n1)

        if [ -n "\$BEST_HIT" ]; then
            BEST_REF=\$(echo "\$BEST_HIT" | awk '{print \$1}')
            BEST_ANI=\$(echo "\$BEST_HIT" | awk '{print \$3}')
            BEST_FRAGS=\$(echo "\$BEST_HIT" | awk '{print \$4}')
            TOTAL_FRAGS=\$(echo "\$BEST_HIT" | awk '{print \$5}')
            N_HITS=\$(wc -l < ${prefix}.ani.txt)

            # Filter by minimum ANI
            N_PASSING=\$(awk -v min=${min_ani} '\$3 >= min' ${prefix}.ani.txt | wc -l)

            cat <<-EOF > ${prefix}.stats.json
\t{
\t  "success": true,
\t  "cluster_id": "${meta.cluster_id}",
\t  "n_references": \$N_REFS,
\t  "n_hits": \$N_HITS,
\t  "n_passing_threshold": \$N_PASSING,
\t  "min_ani_threshold": ${min_ani},
\t  "best_ani": \$BEST_ANI,
\t  "best_reference": "\$BEST_REF",
\t  "best_fragments_aligned": \$BEST_FRAGS,
\t  "best_total_fragments": \$TOTAL_FRAGS,
\t  "coverage": \$(echo "scale=2; \$BEST_FRAGS / \$TOTAL_FRAGS * 100" | bc)
\t}
\tEOF

            echo "  Best match: \$BEST_REF (ANI: \$BEST_ANI%)" >&2
            echo "  Passing threshold: \$N_PASSING / \$N_HITS hits" >&2
        else
            # Empty results file
            cat <<-EOF > ${prefix}.stats.json
\t{
\t  "success": false,
\t  "cluster_id": "${meta.cluster_id}",
\t  "n_references": \$N_REFS,
\t  "n_hits": 0,
\t  "best_ani": null,
\t  "best_reference": null,
\t  "error": "No ANI results generated"
\t}
\tEOF
        fi
    else
        echo "✗ FastANI failed or no significant matches found" >&2

        # Create empty results
        touch ${prefix}.ani.txt

        cat <<-EOF > ${prefix}.stats.json
\t{
\t  "success": false,
\t  "cluster_id": "${meta.cluster_id}",
\t  "n_references": \$N_REFS,
\t  "n_hits": 0,
\t  "best_ani": null,
\t  "best_reference": null,
\t  "exit_code": \$FASTANI_EXIT,
\t  "error": "No significant ANI matches found (ANI too low or fragments insufficient)"
\t}
\tEOF
    fi

    # Version tracking
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fastani: \$(fastANI --version 2>&1 | grep -oP 'version \\K[0-9.]+' || echo "1.34")
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}_cluster${meta.cluster_id}"
    """
    # Create stub ANI results
    cat <<-EOF > ${prefix}.ani.txt
\tref_genome_1.fasta\t${query}\t96.5\t450\t500
\tref_genome_2.fasta\t${query}\t94.2\t430\t500
\tref_genome_3.fasta\t${query}\t91.8\t410\t500
\tEOF

    # Create stub statistics
    cat <<-EOF > ${prefix}.stats.json
\t{
\t  "success": true,
\t  "cluster_id": "${meta.cluster_id}",
\t  "n_references": 10,
\t  "n_hits": 3,
\t  "n_passing_threshold": 3,
\t  "min_ani_threshold": 80.0,
\t  "best_ani": 96.5,
\t  "best_reference": "ref_genome_1.fasta",
\t  "best_fragments_aligned": 450,
\t  "best_total_fragments": 500,
\t  "coverage": 90.0
\t}
\tEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fastani: 1.34
    END_VERSIONS
    """
}
