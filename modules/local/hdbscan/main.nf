process HDBSCAN {
    tag "$meta.id"
    label 'process_high_memory'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/hdbscan:0.8.33' :
        'quay.io/biocontainers/hdbscan:0.8.33' }"

    input:
    tuple val(meta), path(umap_coords)
    val min_cluster_size
    val min_samples
    val cluster_selection_epsilon

    output:
    tuple val(meta), path("*.clusters.tsv")      , emit: clusters
    tuple val(meta), path("*.cluster_info.json") , emit: cluster_info
    tuple val(meta), path("*.clusters_plot.png") , emit: plot
    path "versions.yml"                           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def random_state = task.ext.random_state ?: 42  // Reproducibility
    def selection_method = task.ext.cluster_selection_method ?: 'eom'
    def dimensions = task.ext.dimensions ?: 'UMAP1,UMAP2'  // Which UMAP dims to use
    """
    hdbscan_cluster.py \\
        --input $umap_coords \\
        --output ${prefix}.clusters.tsv \\
        --plot ${prefix}.clusters_plot.png \\
        --cluster-info ${prefix}.cluster_info.json \\
        --min-cluster-size $min_cluster_size \\
        --min-samples ${min_samples ?: min_cluster_size} \\
        --cluster-selection-epsilon $cluster_selection_epsilon \\
        --cluster-selection-method $selection_method \\
        --dimensions $dimensions \\
        --random-state $random_state \\
        $args

    # Check if clustering succeeded (exit code 1 = no clusters found)
    if [ \$? -eq 1 ]; then
        echo "WARNING: No clusters found with current parameters!" >&2
        echo "Consider adjusting min_cluster_size or other parameters." >&2
        # Don't fail the pipeline, just warn
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version 2>&1 | sed 's/Python //g')
        hdbscan: \$(python -c "import hdbscan; print(hdbscan.__version__)")
        numpy: \$(python -c "import numpy; print(numpy.__version__)")
        pandas: \$(python -c "import pandas; print(pandas.__version__)")
        scikit-learn: \$(python -c "import sklearn; print(sklearn.__version__)")
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Create stub cluster assignments with realistic structure
    cat <<-EOF > ${prefix}.clusters.tsv
\tread\tlength\tUMAP1\tUMAP2\tcluster_id
\tread_001\t1500\t0.5\t1.2\t0
\tread_002\t1600\t0.6\t1.3\t0
\tread_003\t1550\t-0.2\t0.8\t1
\tread_004\t1580\t-0.1\t0.9\t1
\tread_005\t1520\t2.0\t-1.5\t2
\tread_006\t1490\t10.0\t10.0\t-1
\tEOF

    # Create stub cluster info
    cat <<-EOF > ${prefix}.cluster_info.json
\t{
\t  "n_reads": 6,
\t  "n_clusters": 3,
\t  "n_noise": 1,
\t  "noise_fraction": 0.167,
\t  "cluster_sizes": {
\t    "0": 2,
\t    "1": 2,
\t    "2": 1
\t  },
\t  "largest_cluster": 2,
\t  "smallest_cluster": 1,
\t  "mean_cluster_size": 1.67
\t}
\tEOF

    # Create stub plot
    touch ${prefix}.clusters_plot.png

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: 3.10.0
        hdbscan: 0.8.33
        numpy: 1.24.3
        pandas: 1.5.3
        scikit-learn: 1.2.2
    END_VERSIONS
    """
}
