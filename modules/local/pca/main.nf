process PCA {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/scikit-learn:1.4.2--py311h1f0f07a_0' :
        'quay.io/biocontainers/scikit-learn:1.4.2--py311h1f0f07a_0' }"

    input:
    tuple val(meta), path(kmer_freqs), path(kmer_freqs_metadata)
    val n_components

    output:
    tuple val(meta), path("*.pca_features.tsv")     , emit: features
    tuple val(meta), path("*.variance_explained.json"), emit: variance_report
    path "versions.yml"                              , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def random_state = task.ext.random_state ?: 42
    def min_variance = task.ext.min_variance ?: 0.99
    """

    # Run PCA preprocessing
    pca_preprocess.py \\
        --input $kmer_freqs \\
        --output ${prefix}.pca_features.tsv \\
        --variance-report ${prefix}.variance_explained.json \\
        --n-components $n_components \\
        --min-variance $min_variance \\
        --random-state $random_state \\
        $args \\
        --verbose

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version 2>&1 | sed 's/Python //g')
        scikit-learn: \$(python -c "import sklearn; print(sklearn.__version__)")
        numpy: \$(python -c "import numpy; print(numpy.__version__)")
        pandas: \$(python -c "import pandas; print(pandas.__version__)")
        scipy: \$(python -c "import scipy; print(scipy.__version__)")
    END_VERSIONS
    """


    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """

    # Create stub PCA features file
    echo -e "read\\tlength\\tPC1\\tPC2\\tPC3" > ${prefix}.pca_features.tsv
    echo -e "read_001\\t1500\\t0.5\\t1.2\\t-0.3" >> ${prefix}.pca_features.tsv
    echo -e "read_002\\t1600\\t-0.2\\t0.8\\t1.1" >> ${prefix}.pca_features.tsv
    echo -e "read_003\\t1550\\t1.0\\t-0.5\\t0.2" >> ${prefix}.pca_features.tsv

    # Create stub variance report
    cat <<-END_JSON > ${prefix}.variance_explained.json
    {
        "input_dimensions": 131072,
        "output_dimensions": 50,
        "total_variance_explained": 0.995,
        "memory_reduction_factor": 2621.44
    }
    END_JSON

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: 3.11.0
        scikit-learn: 1.4.2
        numpy: 1.26.0
        pandas: 2.0.0
        scipy: 1.11.0
    END_VERSIONS
    """

}
