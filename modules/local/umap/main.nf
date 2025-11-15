process UMAP {
    tag "$meta.id"
    label 'process_high'  // High memory and CPU requirements

    // Memory requirements (5x base memory for UMAP overhead):
    // - 1k reads × 131k features: ~5.2 GB
    // - 10k reads × 131k features: ~52 GB
    // - 50k reads × 131k features: ~260 GB
    // - 100k reads × 131k features: ~525 GB
    //
    // Use --umap_set_size to control input size and memory usage
    // Recommended: 10k-50k reads for desktop/laptop, 100k for servers

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/umap-learn:0.5.6--py311hca9a8f5_0' :
        'quay.io/biocontainers/umap-learn:0.5.6--py311hca9a8f5_0' }"

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
    # Memory validation: estimate requirements and check available memory
    # This prevents OOM crashes and provides helpful error messages
    echo "Checking memory requirements..." >&2
    umap_memory_check.py \\
        --input $kmer_freqs \\
        --safety-factor 5.0 || {
        echo "ERROR: Insufficient memory for UMAP!" >&2
        echo "Consider using --umap_set_size to reduce input reads" >&2
        exit 1
    }

    # Run UMAP dimensionality reduction
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
        psutil: \$(python -c "import psutil; print(psutil.__version__)")
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
