process CREATE_PHYLOSEQ {
    tag "$meta.id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/mulled-v2-0baa20a6ee87f2c19600a0c54f070da0f6c4c0f5:ec2c5e6c906c3e7b292cb4c35e5b5feadc83d84e-0' :
        'quay.io/biocontainers/mulled-v2-0baa20a6ee87f2c19600a0c54f070da0f6c4c0f5:ec2c5e6c906c3e7b292cb4c35e5b5feadc83d84e-0' }"

    input:
    tuple val(meta), path(phylotree), path(abundances), path(taxonomy)
    val calculate_diversity

    output:
    tuple val(meta), path("*.rds")        , emit: phyloseq
    tuple val(meta), path("*_summary.txt"), emit: summary
    path "versions.yml"                    , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def diversity_flag = calculate_diversity ? '--calculate-diversity' : ''
    """
    create_phyloseq_object.R \\
        --tree ${phylotree} \\
        --abundance ${abundances} \\
        --taxonomy ${taxonomy} \\
        --output ${prefix}_phyloseq.rds \\
        --verbose \\
        ${diversity_flag} ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        r-base: \$(R --version | head -1 | sed 's/R version //' | sed 's/ (.*//')
        phyloseq: \$(Rscript -e "cat(as.character(packageVersion('phyloseq')))")
        ape: \$(Rscript -e "cat(as.character(packageVersion('ape')))")
        picante: \$(Rscript -e "cat(as.character(packageVersion('picante')))")
        vegan: \$(Rscript -e "cat(as.character(packageVersion('vegan')))")
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Create placeholder phyloseq RDS file
    touch ${prefix}_phyloseq.rds

    # Create placeholder summary
    cat <<-EOF > ${prefix}_phyloseq_summary.txt
    NanoPulse phyloseq Object Summary (STUB MODE)
    ==============================================

    Created: \$(date)

    Input files:
      Tree: ${phylotree}
      Abundance: ${abundances}
      Taxonomy: ${taxonomy}

    Status: STUB MODE - No actual processing performed
    EOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        r-base: 4.3.0
        phyloseq: 1.44.0
        ape: 5.7
        picante: 1.8.2
        vegan: 2.6-4
    END_VERSIONS
    """
}
