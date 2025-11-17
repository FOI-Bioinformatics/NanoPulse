process SPLITCLUSTERS {
    tag "$meta.id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/biopython:1.83--py311h9b8898c_1' :
        'quay.io/biocontainers/biopython:1.83--py311h9b8898c_1' }"

    input:
    tuple val(meta), path(reads), path(cluster_assignments)

    output:
    tuple val(meta), path("cluster_*.fastq")   , emit: clustered_reads
    tuple val(meta), path("unclustered.fastq") , emit: unclustered, optional: true
    tuple val(meta), path("cluster_stats.json"), emit: stats
    path "versions.yml"                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """

    #!/usr/bin/env python3

    from Bio import SeqIO
    import json
    import sys

    print("Loading cluster assignments...", file=sys.stderr)

    # Read cluster assignments
    cluster_map = {}
    with open("$cluster_assignments") as f:
        header = next(f)  # Skip header
        for line in f:
            parts = line.strip().split('\\t')
            read_id = parts[0]
            cluster_id = int(parts[-1])  # Last column is cluster_id
            cluster_map[read_id] = cluster_id

    print(f"Loaded assignments for {len(cluster_map)} reads", file=sys.stderr)

    # Split reads by cluster
    cluster_files = {}
    unclustered_file = None
    read_counts = {}
    total_reads = 0
    skipped_reads = 0

    print("Splitting reads by cluster...", file=sys.stderr)

    for record in SeqIO.parse("$reads", "fastq"):
        total_reads += 1
        read_id = record.id

        # Handle reads not in cluster map (shouldn't happen, but be defensive)
        if read_id not in cluster_map:
            skipped_reads += 1
            continue

        cluster_id = cluster_map[read_id]

        # Handle unclustered reads (cluster_id = -1)
        if cluster_id == -1:
            if unclustered_file is None:
                unclustered_file = open("unclustered.fastq", "w")
                read_counts[-1] = 0
            SeqIO.write(record, unclustered_file, "fastq")
            read_counts[-1] += 1

        # Handle clustered reads
        else:
            if cluster_id not in cluster_files:
                cluster_files[cluster_id] = open(f"cluster_{cluster_id}.fastq", "w")
                read_counts[cluster_id] = 0
            SeqIO.write(record, cluster_files[cluster_id], "fastq")
            read_counts[cluster_id] += 1

        # Progress indicator
        if total_reads % 10000 == 0:
            print(f"  Processed {total_reads} reads...", file=sys.stderr)

    # Close all files
    for f in cluster_files.values():
        f.close()
    if unclustered_file:
        unclustered_file.close()

    # Generate statistics
    n_clusters = len([c for c in read_counts.keys() if c != -1])
    n_unclustered = read_counts.get(-1, 0)
    n_clustered = sum(v for k, v in read_counts.items() if k != -1)

    stats = {
        'total_reads': total_reads,
        'skipped_reads': skipped_reads,
        'n_clusters': n_clusters,
        'n_clustered_reads': n_clustered,
        'n_unclustered_reads': n_unclustered,
        'cluster_sizes': {k: v for k, v in read_counts.items() if k != -1}
    }

    # Save statistics
    with open("cluster_stats.json", "w") as f:
        json.dump(stats, f, indent=2)

    # Report
    print(f"\\nSplitting complete!", file=sys.stderr)
    print(f"  Total reads processed: {total_reads}", file=sys.stderr)
    print(f"  Clusters created: {n_clusters}", file=sys.stderr)
    print(f"  Clustered reads: {n_clustered}", file=sys.stderr)
    print(f"  Unclustered reads: {n_unclustered}", file=sys.stderr)
    if skipped_reads > 0:
        print(f"  WARNING: {skipped_reads} reads skipped (not in cluster assignments)", file=sys.stderr)

    if n_clusters == 0:
        print(f"  ERROR: No clusters created! Check clustering parameters.", file=sys.stderr)
        sys.exit(1)

    # Version tracking
    import Bio
    with open("versions.yml", "w") as f:
        f.write('"${task.process}":\\n')
        f.write(f'    python: {sys.version.split()[0]}\\n')
        f.write(f'    biopython: {Bio.__version__}\\n')
    """


    stub:
    """

    # Create stub cluster files
    touch cluster_0.fastq cluster_1.fastq cluster_2.fastq
    touch unclustered.fastq

    # Create stub statistics
    cat <<-EOF > cluster_stats.json
    {
      "total_reads": 1000,
      "skipped_reads": 0,
      "n_clusters": 3,
      "n_clustered_reads": 950,
      "n_unclustered_reads": 50,
      "cluster_sizes": {
        "0": 400,
        "1": 350,
        "2": 200
      }
    }
    EOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: 3.10.0
        biopython: 1.78
    END_VERSIONS
    """

}
