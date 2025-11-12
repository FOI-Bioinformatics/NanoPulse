process JOINCONSENSUS {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'biocontainers/python:3.11' }"

    input:
    tuple val(meta), path(consensus_files), path(classification_files)

    output:
    tuple val(meta), path("*_all_consensus.fasta")    , emit: fasta
    tuple val(meta), path("*_consensus_annotations.tsv"), emit: annotations
    tuple val(meta), path("*_consensus_summary.json")   , emit: summary
    path "versions.yml"                                  , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    join_consensus.py \\
        --consensus ${consensus_files.join(' ')} \\
        --classifications ${classification_files.join(' ')} \\
        --output_fasta ${prefix}_all_consensus.fasta \\
        --output_tsv ${prefix}_consensus_annotations.tsv \\
        --output_json ${prefix}_consensus_summary.json \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_all_consensus.fasta
    touch ${prefix}_consensus_annotations.tsv
    echo '{"total_clusters": 0}' > ${prefix}_consensus_summary.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //')
    END_VERSIONS
    """
}
