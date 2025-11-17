process DRAFT_SELECTION {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/fastani:1.33--h2e03b76_0' :
        'quay.io/biocontainers/fastani:1.33--h2e03b76_0' }"

    input:
    tuple val(meta), path(corrected_reads)

    output:
    tuple val(meta), path("*_draft.fasta")     , emit: draft
    tuple val(meta), path("*.ani.tsv")         , emit: ani_results
    tuple val(meta), path("*.selection.json")  , emit: stats
    path "versions.yml"                        , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}_cluster${meta.cluster_id}"
    def kmer = task.ext.kmer ?: 16
    def frag_len = task.ext.frag_len ?: 160
    """

    # Split corrected reads into individual files (one read per file)
    split -l 2 ${corrected_reads} split_reads_

    # Create list of read files
    find . -name "split_reads_*" -type f > read_list.txt

    # Count reads
    N_READS=\$(wc -l < read_list.txt)

    if [ \$N_READS -eq 0 ]; then
        echo "ERROR: No reads found in corrected reads file" >&2
        exit 1
    elif [ \$N_READS -eq 1 ]; then
        # Only one read - use it as draft
        echo "INFO: Only 1 read available, using it as draft" >&2
        DRAFT_FILE=\$(head -n1 read_list.txt)
        cat \$DRAFT_FILE > ${prefix}_draft.fasta
        DRAFT_ID=\$(head -n1 ${prefix}_draft.fasta | sed 's/>//g')

        # Create empty ANI results (no comparison needed)
        echo -e "query\\treference\\tANI\\tmatches\\ttotal_frags" > ${prefix}.ani.tsv

        # Statistics
        cat <<-EOF > ${prefix}.selection.json
\t{
\t  "n_reads": 1,
\t  "draft_id": "\$DRAFT_ID",
\t  "avg_ani": null,
\t  "selection_method": "single_read",
\t  "cluster_id": "${meta.cluster_id}"
\t}
\tEOF
    else
        # Multiple reads - run fastANI all-vs-all
        echo "INFO: Running fastANI on \$N_READS reads" >&2

        fastANI \\
            --ql read_list.txt \\
            --rl read_list.txt \\
            -o ${prefix}.ani.tsv \\
            -t ${task.cpus} \\
            -k ${kmer} \\
            --fragLen ${frag_len} \\
            ${args}

        # Calculate average ANI for each read
        # Format: query ref ANI matches total
        # For each read, calculate average ANI to all other reads
        DRAFT_FILE=\$(awk 'NR>1 {
            name[\$1] = \$1
            arr[\$1] += \$3
            count[\$1] += 1
        }
        END {
            for (a in arr) {
                print arr[a] / count[a], name[a]
            }
        }' ${prefix}.ani.tsv | sort -rg | head -n1 | cut -d " " -f2)

        # Extract draft read
        cat \$DRAFT_FILE > ${prefix}_draft.fasta
        DRAFT_ID=\$(head -n1 ${prefix}_draft.fasta | sed 's/>//g')

        # Get average ANI for the selected draft
        AVG_ANI=\$(awk -v draft="\$DRAFT_FILE" 'NR>1 {
            if (\$1 == draft) {
                arr[\$1] += \$3
                count[\$1] += 1
            }
        }
        END {
            for (a in arr) {
                print arr[a] / count[a]
            }
        }' ${prefix}.ani.tsv)

        # Statistics
        cat <<-EOF > ${prefix}.selection.json
\t{
\t  "n_reads": \$N_READS,
\t  "draft_id": "\$DRAFT_ID",
\t  "avg_ani": \$AVG_ANI,
\t  "selection_method": "fastani_max_avg",
\t  "cluster_id": "${meta.cluster_id}"
\t}
\tEOF

        echo "+ Selected draft: \$DRAFT_ID (avg ANI: \$AVG_ANI)" >&2
    fi

    # Version tracking
    cat <<END_VERSIONS > versions.yml
"${task.process}":
    fastani: \$(fastANI --version 2>&1 | grep -oP '(?<=version )\\S+' || echo "1.33")
END_VERSIONS
    """


    stub:
    def prefix = task.ext.prefix ?: "${meta.id}_cluster${meta.cluster_id}"
    """

    # Create stub draft read
    cat <<-EOF > ${prefix}_draft.fasta
\t>draft_read_1
\tACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
\tACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
\tEOF

    # Create stub ANI results
    cat <<-EOF > ${prefix}.ani.tsv
\tquery\treference\tANI\tmatches\ttotal_frags
\tsplit_reads_aa\tsplit_reads_ab\t98.5\t50\t50
\tsplit_reads_aa\tsplit_reads_ac\t97.2\t48\t50
\tsplit_reads_ab\tsplit_reads_aa\t98.5\t50\t50
\tEOF

    # Create stub statistics
    cat <<-EOF > ${prefix}.selection.json
\t{
\t  "n_reads": 10,
\t  "draft_id": "draft_read_1",
\t  "avg_ani": 97.85,
\t  "selection_method": "fastani_max_avg",
\t  "cluster_id": "${meta.cluster_id}"
\t}
\tEOF

    cat <<END_VERSIONS > versions.yml
"${task.process}":
    fastani: 1.33
END_VERSIONS
    """

}
