process RESCUE_NOISE {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/vsearch:2.28.1--h6a68c12_2' :
        'quay.io/biocontainers/vsearch:2.28.1--h6a68c12_2' }"

    input:
    tuple val(meta), path(reads), path(clusters_tsv)
    val identity_threshold
    val min_abundance

    output:
    tuple val(meta), path("*.rescued_clusters.tsv")  , emit: clusters
    tuple val(meta), path("*.rescued_consensus.fasta"), emit: consensus, optional: true
    tuple val(meta), path("*.rescue_stats.json")      , emit: stats
    path "versions.yml"                                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def id_threshold = identity_threshold ?: 0.70
    def min_size = min_abundance ?: 5
    """
    # Extract noise points (cluster_id = -1) from HDBSCAN output
    awk '\$5 == -1 {print \$1}' $clusters_tsv > noise_reads.txt

    # Count noise reads
    NOISE_COUNT=\$(wc -l < noise_reads.txt)
    echo "Found \$NOISE_COUNT noise reads for secondary clustering"

    # Initialize output files
    cp $clusters_tsv ${prefix}.rescued_clusters.tsv
    echo '{"noise_reads": 0, "rescued_clusters": 0, "rescued_reads": 0, "final_noise": 0}' > ${prefix}.rescue_stats.json

    if [ "\$NOISE_COUNT" -gt 0 ]; then
        # Extract noise reads from original FASTQ
        seqtk subseq $reads noise_reads.txt > noise_reads.fastq

        # Secondary clustering with vsearch
        # Convert FASTQ to FASTA for vsearch
        seqtk seq -A noise_reads.fastq > noise_reads.fasta

        # Run vsearch clustering
        vsearch \\
            --cluster_fast noise_reads.fasta \\
            --id $id_threshold \\
            --minuniquesize $min_size \\
            --threads $task.cpus \\
            --centroids noise_centroids.fasta \\
            --uc noise_clusters.uc \\
            --consout ${prefix}.rescued_consensus.fasta \\
            $args

        # Validate vsearch succeeded
        if [ ! -f "noise_clusters.uc" ]; then
            echo "ERROR: vsearch clustering failed - no output file generated" >&2
            exit 1
        fi

        # Parse vsearch results to update cluster assignments
        # Assign new cluster IDs starting after existing max cluster ID
        MAX_CLUSTER=\$(awk 'NR>1 && \$5 != -1 {print \$5}' $clusters_tsv | sort -n | tail -1)
        MAX_CLUSTER=\${MAX_CLUSTER:-0}
        NEXT_CLUSTER=\$((MAX_CLUSTER + 1))

        # Parse .uc file to create rescue mapping
        awk -v next=\$NEXT_CLUSTER 'BEGIN {cluster_map[0]=0}
             \$1=="C" {cluster_map[\$2]=next; next++}
             \$1=="H" {print \$9, cluster_map[\$2]}' \\
            noise_clusters.uc > rescue_mapping.txt

        # Update cluster assignments using external Python script
        update_rescued_clusters.py \\
            --clusters $clusters_tsv \\
            --mapping rescue_mapping.txt \\
            --output ${prefix}.rescued_clusters.tsv \\
            --stats ${prefix}.rescue_stats.json \\
            --noise-count \$NOISE_COUNT
    else
        echo "No noise reads found - skipping rescue clustering"
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        vsearch: \$(vsearch --version 2>&1 | head -1 | sed 's/vsearch //g' | sed 's/,.*//g')
        seqtk: \$(seqtk 2>&1 | grep 'Version' | sed 's/Version: //g')
        python: \$(python3 --version 2>&1 | sed 's/Python //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Create stub rescued clusters TSV (copy original with some noise points rescued)
    cat <<-EOF > ${prefix}.rescued_clusters.tsv
\tread\tlength\tUMAP1\tUMAP2\tcluster_id
\tread_001\t1500\t0.5\t1.2\t0
\tread_002\t1600\t0.6\t1.3\t0
\tread_003\t1550\t-0.2\t0.8\t1
\tread_004\t1580\t-0.1\t0.9\t1
\tread_005\t1520\t2.0\t-1.5\t2
\tread_006\t1490\t10.0\t10.0\t3
\tread_007\t1510\t9.8\t9.9\t3
\tread_008\t1530\t-10.0\t-10.0\t-1
\tEOF

    # Create stub rescued consensus
    cat <<-EOF > ${prefix}.rescued_consensus.fasta
>cluster_3_rescued consensus=7 seqs=2
ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
\tEOF

    # Create stub statistics
    cat <<-EOF > ${prefix}.rescue_stats.json
\t{
\t  "noise_reads": 3,
\t  "rescued_clusters": 1,
\t  "rescued_reads": 2,
\t  "final_noise": 1,
\t  "rescue_rate": 66.67
\t}
\tEOF

    cat <<END_VERSIONS > versions.yml
"${task.process}":
    vsearch: 2.28.1
    seqtk: 1.4
    python: 3.11.0
END_VERSIONS
    """
}
