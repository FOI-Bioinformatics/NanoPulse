process KMERFREQ {
    tag "$meta.id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/biopython:1.83--py311h9b8898c_1' :
        'quay.io/biocontainers/biopython:1.83--py311h9b8898c_1' }"

    input:
    tuple val(meta), path(reads)
    val kmer_size

    output:
    tuple val(meta), path("*.kmer_freqs.txt.gz"), optional: true, emit: freqs_tsv
    tuple val(meta), path("kmer_freqs.npz"), optional: true, emit: freqs_npz
    tuple val(meta), path("kmer_freqs_metadata.npz"), optional: true, emit: freqs_meta
    path "versions.yml"                          , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Use optimized streaming version for 4-6x speedup
    # Single-pass file reading, no redundant I/O operations
    kmer_freq_streaming.py \\
        --reads $reads \\
        --kmer-size $kmer_size \\
        --threads $task.cpus \\
        $args \\
        | pigz -p $task.cpus -c > ${prefix}.kmer_freqs.txt.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version 2>&1 | sed 's/Python //g')
        biopython: \$(python -c "import Bio; print(Bio.__version__)")
        tqdm: \$(python -c "import tqdm; print(tqdm.__version__)")
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Create stub k-mer frequency file
    echo -e "read_id\\tlength\\tkmer1\\tkmer2\\tkmer3" | pigz -c > ${prefix}.kmer_freqs.txt.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version 2>&1 | sed 's/Python //g' || echo "3.10.0")
        biopython: 1.78
        pandas: 1.5.0
    END_VERSIONS
    """
}
