process EXTRACT_NOVEL_SEQUENCES {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/biopython:1.78' :
        'quay.io/biocontainers/biopython:1.78' }"

    input:
    tuple val(meta), path(consensus_fasta), path(classification_json)
    val novelty_threshold

    output:
    tuple val(meta), path("*.novel.fasta"), emit: novel_sequences, optional: true
    tuple val(meta), path("*.novel_summary.tsv"), emit: summary
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env python3
    import json
    from pathlib import Path
    from Bio import SeqIO
    import sys

    # Read classification results
    with open('${classification_json}') as f:
        classifications = json.load(f)

    # Build map of cluster_id -> confidence/is_novel
    novel_clusters = {}

    # Handle both single classification and list of classifications
    if isinstance(classifications, list):
        # Multiple clusters (aggregated results)
        for classification in classifications:
            cluster_id = classification.get('meta', {}).get('cluster_id')

            # Check if this is probabilistic classification
            if 'classification' in classification:
                # Probabilistic mode
                confidence = classification['classification'].get('confidence', 1.0)
                is_novel = classification['classification'].get('is_novel', False)
            else:
                # Simple voting mode - use confidence level as proxy
                confidence_level = classification.get('confidence', 'high')
                # Convert confidence level to numeric score
                confidence_map = {'high': 0.9, 'medium': 0.7, 'low': 0.5, 'none': 0.0}
                confidence = confidence_map.get(confidence_level, 0.0)
                is_novel = confidence < ${novelty_threshold}

            if cluster_id is not None and (is_novel or confidence < ${novelty_threshold}):
                novel_clusters[cluster_id] = {
                    'confidence': confidence,
                    'is_novel': is_novel,
                    'classification': classification
                }
    else:
        # Single cluster result
        cluster_id = classifications.get('meta', {}).get('cluster_id')

        if 'classification' in classifications:
            confidence = classifications['classification'].get('confidence', 1.0)
            is_novel = classifications['classification'].get('is_novel', False)
        else:
            confidence_level = classifications.get('confidence', 'high')
            confidence_map = {'high': 0.9, 'medium': 0.7, 'low': 0.5, 'none': 0.0}
            confidence = confidence_map.get(confidence_level, 0.0)
            is_novel = confidence < ${novelty_threshold}

        if cluster_id is not None and (is_novel or confidence < ${novelty_threshold}):
            novel_clusters[cluster_id] = {
                'confidence': confidence,
                'is_novel': is_novel,
                'classification': classifications
            }

    # Extract novel sequences from FASTA
    novel_seqs = []
    total_seqs = 0

    for record in SeqIO.parse('${consensus_fasta}', 'fasta'):
        total_seqs += 1

        # Extract cluster ID from header (format: sample_cluster<ID>)
        # Example: mock4_cluster0, mock4_cluster1, etc.
        header_parts = record.id.split('_cluster')
        if len(header_parts) == 2:
            try:
                cluster_id = int(header_parts[1])

                if cluster_id in novel_clusters:
                    # Update description with novelty info
                    conf = novel_clusters[cluster_id]['confidence']
                    record.description = f"{record.description} confidence={conf:.4f} potentially_novel=true"
                    novel_seqs.append(record)
            except ValueError:
                # Could not parse cluster ID
                continue

    # Write novel sequences to FASTA
    if novel_seqs:
        with open('${prefix}.novel.fasta', 'w') as f:
            SeqIO.write(novel_seqs, f, 'fasta')
        print(f"Extracted {len(novel_seqs)} potentially novel sequences", file=sys.stderr)
    else:
        # Create empty file to satisfy optional output
        Path('${prefix}.novel.fasta').touch()
        print("No potentially novel sequences identified", file=sys.stderr)

    # Write summary
    with open('${prefix}.novel_summary.tsv', 'w') as f:
        f.write("Sample\\tTotal_Sequences\\tNovel_Sequences\\tNovelty_Threshold\\tNovel_Percentage\\n")
        novel_pct = (len(novel_seqs) / total_seqs * 100) if total_seqs > 0 else 0.0
        f.write(f"${meta.id}\\t{total_seqs}\\t{len(novel_seqs)}\\t${novelty_threshold}\\t{novel_pct:.2f}\\n")

        # Write details for each novel cluster
        f.write("\\n# Novel Cluster Details\\n")
        f.write("Cluster_ID\\tConfidence\\tClassification\\tMethod\\n")

        for cluster_id in sorted(novel_clusters.keys()):
            info = novel_clusters[cluster_id]
            conf = info['confidence']

            # Extract classification name
            classification_data = info['classification']
            if 'classification' in classification_data:
                # Probabilistic mode
                name = classification_data['classification'].get('name', 'Unknown')
                method = classification_data['classification'].get('method', 'EM_probabilistic')
            else:
                # Simple voting mode
                name = classification_data.get('consensus', {}).get('name', 'Unknown')
                method = classification_data.get('consensus', {}).get('method', 'Unknown')

            f.write(f"{cluster_id}\\t{conf:.4f}\\t{name}\\t{method}\\n")

    print(f"Summary: {len(novel_seqs)}/{total_seqs} sequences ({novel_pct:.2f}%) potentially novel", file=sys.stderr)

    # Generate versions.yml
    import platform
    python_version = platform.python_version()

    try:
        import Bio
        biopython_version = Bio.__version__
    except:
        biopython_version = "1.78"

    with open('versions.yml', 'w') as f:
        f.write(f'"${task.process}":\\n')
        f.write(f'    python: {python_version}\\n')
        f.write(f'    biopython: {biopython_version}\\n')
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Create stub novel sequences FASTA
    cat <<-EOF > ${prefix}.novel.fasta
\t>mock4_cluster5 confidence=0.3500 potentially_novel=true
\tATGCATGCATGCATGCATGCATGCATGCATGCATGC
\t>mock4_cluster7 confidence=0.4200 potentially_novel=true
\tGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTA
\tEOF

    # Create stub summary
    cat <<-EOF > ${prefix}.novel_summary.tsv
\tSample\tTotal_Sequences\tNovel_Sequences\tNovelty_Threshold\tNovel_Percentage
\t${meta.id}\t10\t2\t${novelty_threshold}\t20.00

\t# Novel Cluster Details
\tCluster_ID\tConfidence\tClassification\tMethod
\t5\t0.3500\tUnknown bacterium\tEM_probabilistic
\t7\t0.4200\tNovel Firmicutes\tEM_probabilistic
\tEOF

    cat <<-END_VERSIONS > versions.yml
"${task.process}":
    python: 3.11.0
    biopython: 1.78
END_VERSIONS
    """

}
