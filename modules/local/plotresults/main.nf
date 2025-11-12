process PLOTRESULTS {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/mulled-v2-ad9dd5f398966bf899ae05f8e7c54d0fb10cdfa7:05678da05b8e5a7a5130e90a9f9a6c585b965afa-0' :
        'biocontainers/mulled-v2-ad9dd5f398966bf899ae05f8e7c54d0fb10cdfa7:05678da05b8e5a7a5130e90a9f9a6c585b965afa-0' }"

    input:
    tuple val(meta), path(umap_vectors), path(clusters), path(abundances), path(annotations)

    output:
    tuple val(meta), path("*.png")                       , emit: plots
    tuple val(meta), path("*_plots_report.html")        , emit: html
    tuple val(meta), path("*_plot_summary.json")        , emit: summary
    path "versions.yml"                                  , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    plot_results.py \\
        --umap_vectors ${umap_vectors} \\
        --clusters ${clusters} \\
        --abundances ${abundances} \\
        --annotations ${annotations} \\
        --output_prefix ${prefix} \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //')
        matplotlib: \$(python -c "import matplotlib; print(matplotlib.__version__)")
        pandas: \$(python -c "import pandas; print(pandas.__version__)")
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_umap_clustering.png
    touch ${prefix}_abundance_distribution.png
    touch ${prefix}_taxonomy_composition.png
    echo "<html><body>Stub plot report</body></html>" > ${prefix}_plots_report.html
    echo '{"plots_generated": 0}' > ${prefix}_plot_summary.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //')
        matplotlib: 3.7.0
        pandas: 1.5.2
    END_VERSIONS
    """
}
