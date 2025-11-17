process AGGREGATE_CLASSIFICATIONS {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'quay.io/biocontainers/python:3.11' }"

    input:
    tuple val(meta), path(classification_jsons)

    output:
    tuple val(meta), path("*.aggregated_classifications.json"), emit: aggregated
    path "versions.yml"                                        , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Aggregate classifications using external Python script
    aggregate_classifications.py \\
        --input ${classification_jsons} \\
        --output ${prefix}.aggregated_classifications.json \\
        --verbose

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version 2>&1 | sed 's/Python //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Create stub aggregated JSON with 3 sample classifications
    cat <<-EOF > ${prefix}.aggregated_classifications.json
\t[
\t  {
\t    "meta": {"id": "${meta.id}", "cluster_id": 0},
\t    "classification": {
\t      "name": "Escherichia coli",
\t      "taxid": "562",
\t      "rank": "species",
\t      "method": "EM_probabilistic",
\t      "confidence": 0.95,
\t      "is_novel": false
\t    }
\t  },
\t  {
\t    "meta": {"id": "${meta.id}", "cluster_id": 1},
\t    "classification": {
\t      "name": "Unknown bacterium",
\t      "taxid": null,
\t      "rank": "unknown",
\t      "method": "EM_probabilistic",
\t      "confidence": 0.35,
\t      "is_novel": true
\t    }
\t  },
\t  {
\t    "meta": {"id": "${meta.id}", "cluster_id": 2},
\t    "classification": {
\t      "name": "Staphylococcus aureus",
\t      "taxid": "1280",
\t      "rank": "species",
\t      "method": "EM_probabilistic",
\t      "confidence": 0.88,
\t      "is_novel": false
\t    }
\t  }
\t]
\tEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: 3.11.0
    END_VERSIONS
    """

}
