process BUILD_PHYLOTREE {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/mulled-v2-0baa20a6ee87f2c19600a0c54f070da0f6c4c0f5:ec2c5e6c906c3e7b292cb4c35e5b5feadc83d84e-0' :
        'quay.io/biocontainers/mulled-v2-0baa20a6ee87f2c19600a0c54f070da0f6c4c0f5:ec2c5e6c906c3e7b292cb4c35e5b5feadc83d84e-0' }"

    input:
    tuple val(meta), path(consensus_fasta)
    val alignment_method

    output:
    tuple val(meta), path("*.aln.fasta")    , emit: alignment
    tuple val(meta), path("*.tree")         , emit: tree
    tuple val(meta), path("*.tree_stats.txt"), emit: stats
    path "versions.yml"                      , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def mafft_args = alignment_method == 'auto' ? '--auto' : '--retree 2 --maxiterate 2'
    """
    # Check if we have enough sequences for tree building (minimum 3)
    num_seqs=\$(grep -c "^>" ${consensus_fasta})

    if [ "\$num_seqs" -lt 3 ]; then
        echo "Warning: Only \$num_seqs sequences found. Need at least 3 for tree building." >&2
        echo "Creating placeholder outputs..." >&2

        # Create empty alignment (copy original)
        cp ${consensus_fasta} ${prefix}.aln.fasta

        # Create placeholder tree
        echo "();" > ${prefix}.tree

        # Create stats file
        cat <<-EOF > ${prefix}.tree_stats.txt
\tPhylogenetic Tree Statistics
\tSample: ${meta.id}
\tSequences: \$num_seqs
\tStatus: SKIPPED (need minimum 3 sequences)
\tEOF
    else
        # Perform multiple sequence alignment with MAFFT
        echo "Aligning \$num_seqs sequences with MAFFT..."
        mafft ${mafft_args} \\
            --thread ${task.cpus} \\
            ${consensus_fasta} \\
            > ${prefix}.aln.fasta

        # Build phylogenetic tree with FastTree
        echo "Building phylogenetic tree with FastTree..."
        FastTree -nt \\
            -gtr \\
            -gamma \\
            -log ${prefix}.fasttree.log \\
            ${prefix}.aln.fasta \\
            > ${prefix}.tree

        # Extract tree statistics from FastTree log
        cat <<-EOF > ${prefix}.tree_stats.txt
\tPhylogenetic Tree Statistics
\tSample: ${meta.id}
\tSequences: \$num_seqs
\tAlignment length: \$(head -2 ${prefix}.aln.fasta | tail -1 | wc -c)
\tModel: GTR+Gamma
\tLog-likelihood: \$(grep "Gamma20LogLk" ${prefix}.fasttree.log | tail -1 | awk '{print \$2}')
\tTree length: \$(grep "TreeLength" ${prefix}.fasttree.log | tail -1 | awk '{print \$2}')
\tEOF

        echo "Phylogenetic tree constructed successfully"
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mafft: \$(mafft --version 2>&1 | grep -o 'v[0-9.]*' | sed 's/v//')
        fasttree: \$(FastTree 2>&1 | grep version | sed 's/.*version //; s/ .*//')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Create stub alignment
    cat <<-EOF > ${prefix}.aln.fasta
\t>cluster_0
\tATGCATGCATGCATGCATGCATGCATGC
\t>cluster_1
\tATGCATGCATGCATGCATGCATGCATGC
\t>cluster_2
\tGCTAGCTAGCTAGCTAGCTAGCTAGCTA
\tEOF

    # Create stub tree (Newick format)
    echo "(cluster_0:0.1,cluster_1:0.1,cluster_2:0.2);" > ${prefix}.tree

    # Create stub stats
    cat <<-EOF > ${prefix}.tree_stats.txt
\tPhylogenetic Tree Statistics
\tSample: ${meta.id}
\tSequences: 3
\tAlignment length: 28
\tModel: GTR+Gamma
\tLog-likelihood: -120.5
\tTree length: 0.4
\tEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mafft: 7.520
        fasttree: 2.1.11
    END_VERSIONS
    """

}
