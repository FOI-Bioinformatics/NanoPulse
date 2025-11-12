process KMERFREQ {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/biopython:1.78' :
        'biocontainers/biopython:1.78' }"

    input:
    tuple val(meta), path(reads)
    val kmer_size

    output:
    tuple val(meta), path("*.kmer_freqs.txt"), emit: freqs
    path "versions.yml"                       , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    kmer_freq_fixed.py \\
        --reads $reads \\
        --kmer-size $kmer_size \\
        --threads $task.cpus \\
        $args \\
        > ${prefix}.kmer_freqs.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version 2>&1 | sed 's/Python //g')
        biopython: \$(python -c "import Bio; print(Bio.__version__)")
        pandas: \$(python -c "import pandas; print(pandas.__version__)")
        tqdm: \$(python -c "import tqdm; print(tqdm.__version__)")
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Create stub k-mer frequency file
    echo -e "read_id\\tlength\\tkmer1\\tkmer2\\tkmer3" > ${prefix}.kmer_freqs.txt
    echo -e "read_001\\t1500\\t0.1\\t0.2\\t0.3" >> ${prefix}.kmer_freqs.txt
    echo -e "read_002\\t1600\\t0.15\\t0.25\\t0.35" >> ${prefix}.kmer_freqs.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version 2>&1 | sed 's/Python //g' || echo "3.10.0")
        biopython: 1.78
        pandas: 1.5.0
    END_VERSIONS
    """
}
