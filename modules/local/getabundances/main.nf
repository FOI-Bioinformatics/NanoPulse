process GETABUNDANCES {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/pandas:1.5.2' :
        'quay.io/biocontainers/pandas:1.5.2' }"

    input:
    tuple val(meta), path(cluster_stats), path(classification_files)

    output:
    tuple val(meta), path("*_abundances.csv")         , emit: abundances
    tuple val(meta), path("*_diversity_metrics.txt")  , emit: diversity
    tuple val(meta), path("*_abundance_summary.json") , emit: summary
    path "versions.yml"                                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """

    calculate_abundances.py \\
        --cluster_stats ${cluster_stats} \\
        --classifications ${classification_files.join(' ')} \\
        --output_csv ${prefix}_abundances.csv \\
        --output_diversity ${prefix}_diversity_metrics.txt \\
        --output_json ${prefix}_abundance_summary.json \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //')
        pandas: \$(python -c "import pandas; print(pandas.__version__)")
    END_VERSIONS
    """


    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """

    echo "cluster_id,read_count,relative_abundance,taxon" > ${prefix}_abundances.csv
    echo "Shannon diversity: 0.0" > ${prefix}_diversity_metrics.txt
    echo '{"total_reads": 0}' > ${prefix}_abundance_summary.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //')
        pandas: 1.5.2
    END_VERSIONS
    """

}
