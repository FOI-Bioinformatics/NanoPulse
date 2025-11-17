process PACMAP {
    tag "$meta.id"
    label 'process_medium'  // Medium resources - PaCMAP is more efficient than UMAP

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/pacmap:0.7.2--pyhdfd78af_0' :
        'quay.io/biocontainers/pacmap:0.7.2--pyhdfd78af_0' }"

    input:
    tuple val(meta), path(kmer_freqs)
    val n_components
    val n_neighbors

    output:
    tuple val(meta), path("*.umap_coords.tsv"), emit: coords  // Named 'umap_coords' for drop-in compatibility
    tuple val(meta), path("*.pacmap_plot.png") , emit: plot
    path "versions.yml"                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def random_state = task.ext.random_state ?: 42
    def mn_ratio = task.ext.mn_ratio ?: 0.5
    def fp_ratio = task.ext.fp_ratio ?: 2.0
    """

    # Run PaCMAP dimensionality reduction
    # NOTE: Output file is named 'umap_coords.tsv' for drop-in compatibility with UMAP
    pacmap_reduce.py \\
        --input $kmer_freqs \\
        --output ${prefix}.umap_coords.tsv \\
        --plot ${prefix}.pacmap_plot.png \\
        --n-components $n_components \\
        --n-neighbors $n_neighbors \\
        --mn-ratio $mn_ratio \\
        --fp-ratio $fp_ratio \\
        --random-state $random_state \\
        $args \\
        --verbose

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version 2>&1 | sed 's/Python //g')
        pacmap: \$(python -c "import pacmap; print(pacmap.__version__)")
        numpy: \$(python -c "import numpy; print(numpy.__version__)")
        pandas: \$(python -c "import pandas; print(pandas.__version__)")
        scipy: \$(python -c "import scipy; print(scipy.__version__)")
    END_VERSIONS
    """


    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """

    # Create stub PaCMAP coordinates file (named umap_coords for compatibility)
    echo -e "read\\tlength\\tUMAP1\\tUMAP2\\tUMAP3" > ${prefix}.umap_coords.tsv
    echo -e "read_001\\t1500\\t0.5\\t1.2\\t-0.3" >> ${prefix}.umap_coords.tsv
    echo -e "read_002\\t1600\\t-0.2\\t0.8\\t1.1" >> ${prefix}.umap_coords.tsv
    echo -e "read_003\\t1550\\t1.0\\t-0.5\\t0.2" >> ${prefix}.umap_coords.tsv

    # Create stub plot
    touch ${prefix}.pacmap_plot.png

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: 3.11.0
        pacmap: 0.7.2
        numpy: 1.26.0
        pandas: 2.0.0
        scipy: 1.11.0
    END_VERSIONS
    """

}
