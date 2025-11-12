process UMAP {
    tag "$meta.id"
    label 'process_high_memory'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/umap-learn:0.5.3' :
        'quay.io/biocontainers/umap-learn:0.5.3' }"

    input:
    tuple val(meta), path(kmer_freqs)
    val n_components
    val n_neighbors
    val min_dist

    output:
    tuple val(meta), path("*.umap_coords.tsv"), emit: coords
    tuple val(meta), path("*.umap_plot.png")   , emit: plot
    path "versions.yml"                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def random_state = task.ext.random_state ?: 42  // Reproducibility
    """
    umap_reduce.py \\
        --input $kmer_freqs \\
        --output ${prefix}.umap_coords.tsv \\
        --plot ${prefix}.umap_plot.png \\
        --n-components $n_components \\
        --n-neighbors $n_neighbors \\
        --min-dist $min_dist \\
        --random-state $random_state \\
        $args \\
        --verbose

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version 2>&1 | sed 's/Python //g')
        umap-learn: \$(python -c "import umap; print(umap.__version__)")
        numpy: \$(python -c "import numpy; print(numpy.__version__)")
        pandas: \$(python -c "import pandas; print(pandas.__version__)")
        scikit-learn: \$(python -c "import sklearn; print(sklearn.__version__)")
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Create stub UMAP coordinates file
    echo -e "read\\tlength\\tUMAP1\\tUMAP2\\tUMAP3" > ${prefix}.umap_coords.tsv
    echo -e "read_001\\t1500\\t0.5\\t1.2\\t-0.3" >> ${prefix}.umap_coords.tsv
    echo -e "read_002\\t1600\\t-0.2\\t0.8\\t1.1" >> ${prefix}.umap_coords.tsv
    echo -e "read_003\\t1550\\t1.0\\t-0.5\\t0.2" >> ${prefix}.umap_coords.tsv

    # Create stub plot
    touch ${prefix}.umap_plot.png

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: 3.10.0
        umap-learn: 0.5.3
        numpy: 1.24.3
        pandas: 1.5.3
        scikit-learn: 1.2.2
    END_VERSIONS
    """
}
