process CLASSIFY_CONSENSUS {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'quay.io/biocontainers/python:3.11' }"

    input:
    tuple val(meta), val(sources), path(classification_files)

    output:
    tuple val(meta), path("*_classification.csv"), emit: classification
    tuple val(meta), path("*_classification.json"), emit: json
    tuple val(meta), path("*_combined.txt"), emit: combined
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}_cluster${meta.cluster_id}"
    def min_blast_identity = task.ext.min_blast_identity ?: 80.0
    def min_ani_similarity = task.ext.min_ani_similarity ?: 95.0

    // Build arguments based on available classification files
    def kraken2_arg = sources.contains('kraken2') ? "--kraken2 ${classification_files[sources.indexOf('kraken2')]}" : ""
    def blast_arg = sources.contains('blast') ? "--blast ${classification_files[sources.indexOf('blast')]}" : ""
    def fastani_arg = sources.contains('fastani') ? "--fastani ${classification_files[sources.indexOf('fastani')]}" : ""
    """
    classify_consensus.py \\
        --sample-id ${meta.id} \\
        --cluster-id ${meta.cluster_id} \\
        --output-prefix ${prefix} \\
        --min-blast-identity ${min_blast_identity} \\
        --min-ani-similarity ${min_ani_similarity} \\
        ${kraken2_arg} \\
        ${blast_arg} \\
        ${fastani_arg}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version 2>&1 | sed 's/Python //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}_cluster${meta.cluster_id}"
    """
    # Create stub CSV
    cat <<-EOF > ${prefix}_classification.csv
\tSample,Cluster,Method,Classification,Confidence,TaxID,Details
\t${meta.id},${meta.cluster_id},BLAST,Escherichia coli,high,562,"{}"
\tEOF

    # Create stub JSON
    cat <<-EOF > ${prefix}_classification.json
\t{
\t  "meta": {
\t    "id": "${meta.id}",
\t    "cluster_id": "${meta.cluster_id}"
\t  },
\t  "consensus": {
\t    "method": "BLAST",
\t    "name": "Escherichia coli",
\t    "taxid": "562"
\t  },
\t  "confidence": "high"
\t}
\tEOF

    # Create stub combined
    cat <<-EOF > ${prefix}_combined.txt
\tClassification Results for ${meta.id} Cluster ${meta.cluster_id}
\t======================================================================
\t
\tCONSENSUS:
\t  method: BLAST
\t  name: Escherichia coli
\t  taxid: 562
\t
\tOverall Confidence: high
\tEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: 3.11.0
    END_VERSIONS
    """
}
