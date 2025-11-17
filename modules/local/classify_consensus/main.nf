process CLASSIFY_CONSENSUS {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'quay.io/biocontainers/python:3.11' }"

    input:
    tuple val(meta), val(sources), path(classification_files)
    val use_probabilistic_classification

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

    // Choose classification script based on mode
    def classification_script = use_probabilistic_classification ? "classify_consensus_probabilistic.py" : "classify_consensus.py"
    """

    ${classification_script} \\
        --sample-id ${meta.id} \\
        --cluster-id ${meta.cluster_id} \\
        --output-prefix ${prefix} \\
        --min-blast-identity ${min_blast_identity} \\
        --min-ani-similarity ${min_ani_similarity} \\
        ${kraken2_arg} \\
        ${blast_arg} \\
        ${fastani_arg}

    cat <<END_VERSIONS > versions.yml
"${task.process}":
    python: \$(python --version 2>&1 | sed 's/Python //g')
    classification_mode: ${use_probabilistic_classification ? 'probabilistic_EM' : 'simple_voting'}
END_VERSIONS
    """


    stub:
    def prefix = task.ext.prefix ?: "${meta.id}_cluster${meta.cluster_id}"
    def stub_confidence = use_probabilistic_classification ? "0.95" : "high"
    def stub_confidence_level = use_probabilistic_classification ? "high" : "high"
    def stub_is_novel = use_probabilistic_classification ? "false" : ""
    """

    # Create stub CSV
    cat <<-EOF > ${prefix}_classification.csv
\tSample,Cluster,Method,Classification,Confidence,${use_probabilistic_classification ? 'Confidence_Level,Is_Novel,' : ''}TaxID,${use_probabilistic_classification ? 'Sources' : 'Details'}
\t${meta.id},${meta.cluster_id},${use_probabilistic_classification ? 'EM_probabilistic' : 'BLAST'},Escherichia coli,${stub_confidence},${use_probabilistic_classification ? stub_confidence_level + ',false,' : ''}562,${use_probabilistic_classification ? 'blast' : '{}'}
\tEOF

    # Create stub JSON
    cat <<-EOF > ${prefix}_classification.json
\t{
\t  "meta": {
\t    "id": "${meta.id}",
\t    "cluster_id": "${meta.cluster_id}"
\t  },
\t  ${use_probabilistic_classification ? '"classification":' : '"consensus":'} {
\t    "method": "${use_probabilistic_classification ? 'EM_probabilistic' : 'BLAST'}",
\t    "name": "Escherichia coli",
\t    "taxid": "562",
\t    ${use_probabilistic_classification ? '"confidence": 0.95, "confidence_level": "high", "is_novel": false,' : ''}
\t    ${use_probabilistic_classification ? '"source": "blast"' : ''}
\t  },
\t  ${use_probabilistic_classification ? '' : '"confidence": "high",'}
\t  ${use_probabilistic_classification ? '"em_stats": {"iterations": 5, "converged": true, "num_candidates": 3}' : ''}
\t}
\tEOF

    # Create stub combined
    cat <<-EOF > ${prefix}_combined.txt
\t${use_probabilistic_classification ? 'Probabilistic Classification Results - EM Algorithm' : 'Classification Results for ${meta.id} Cluster ${meta.cluster_id}'}
\t${use_probabilistic_classification ? 'Sample: ${meta.id}, Cluster: ${meta.cluster_id}' : ''}
\t======================================================================
\t
\t${use_probabilistic_classification ? 'BEST CLASSIFICATION:' : 'CONSENSUS:'}
\t  ${use_probabilistic_classification ? 'Taxon: Escherichia coli' : 'method: BLAST'}
\t  ${use_probabilistic_classification ? 'Confidence: 0.95 (high)' : 'name: Escherichia coli'}
\t  ${use_probabilistic_classification ? 'Potentially Novel: false' : 'taxid: 562'}
\t  ${use_probabilistic_classification ? 'Sources: blast' : ''}
\t
\t${use_probabilistic_classification ? 'Overall Confidence: high' : 'Overall Confidence: high'}
\tEOF

    cat <<END_VERSIONS > versions.yml
"${task.process}":
    python: 3.11.0
    classification_mode: ${use_probabilistic_classification ? 'probabilistic_EM' : 'simple_voting'}
END_VERSIONS
    """

}
