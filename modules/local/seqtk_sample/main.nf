process SEQTK_SAMPLE {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/seqtk:1.4--he4a0461_2' :
        'biocontainers/seqtk:1.4--he4a0461_2' }"

    input:
    tuple val(meta), path(reads)
    val sample_size

    output:
    tuple val(meta), path("*.sampled.fastq"), emit: reads
    path "versions.yml"                      , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def seed = task.ext.seed ?: 42

    """
    # Count total reads in input
    total_reads=\$(seqtk comp $reads | wc -l)

    # Intelligent subsampling logic:
    # - If total_reads <= sample_size, use all reads (no subsampling needed)
    # - If total_reads > sample_size, subsample to sample_size reads

    if [ "\$total_reads" -le "$sample_size" ]; then
        # Use all reads - just create symlink/copy to maintain consistent output
        echo "Using all \$total_reads reads (dataset smaller than sample_size=$sample_size)"
        cat $reads > ${prefix}.sampled.fastq
    else
        # Subsample to sample_size reads
        echo "Subsampling \$total_reads reads to $sample_size reads"
        seqtk sample -s $seed $args $reads $sample_size > ${prefix}.sampled.fastq
    fi

    # Report actual number of reads in output
    actual_reads=\$(seqtk comp ${prefix}.sampled.fastq | wc -l)
    echo "Output contains \$actual_reads reads"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        seqtk: \$(seqtk 2>&1 | grep -Eo 'Version: [0-9.]+' | sed 's/Version: //')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Create stub output
    touch ${prefix}.sampled.fastq

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        seqtk: 1.4
    END_VERSIONS
    """
}
