#!/usr/bin/env python3
"""
Create comprehensive visualizations for NanoPulse results.

This script generates multiple plots:
- UMAP clustering visualization (colored by cluster and abundance)
- Abundance distribution (bar chart and pie chart)
- Taxonomic composition (stacked bar or pie chart)
- Quality metrics summary
- HTML report combining all plots
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, List, Optional

import matplotlib
matplotlib.use('Agg')  # Non-interactive backend
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np


def load_umap_vectors(umap_file: Path) -> pd.DataFrame:
    """
    Load UMAP vectors.

    Args:
        umap_file: Path to UMAP vectors file

    Returns:
        DataFrame with UMAP coordinates
    """
    # Try reading with header first (modern format from HDBSCAN output)
    df = pd.read_csv(umap_file, sep='\t')

    # Check if this looks like it has a header
    if 'UMAP1' in df.columns or 'UMAP2' in df.columns or 'UMAP3' in df.columns:
        # Already has proper column names, extract just UMAP columns
        umap_cols = [col for col in df.columns if col.startswith('UMAP')]
        if len(umap_cols) >= 2:
            df = df[umap_cols].copy()
            # Ensure standard column names
            if len(umap_cols) == 2:
                df.columns = ['UMAP1', 'UMAP2']
            elif len(umap_cols) == 3:
                df.columns = ['UMAP1', 'UMAP2', 'UMAP3']
        else:
            raise ValueError(f"Found UMAP columns but not enough: {umap_cols}")
    else:
        # No header or different format, re-read without header
        df = pd.read_csv(umap_file, sep='\t', header=None)
        if df.shape[1] == 2:
            df.columns = ['UMAP1', 'UMAP2']
        elif df.shape[1] == 3:
            df.columns = ['UMAP1', 'UMAP2', 'UMAP3']
        else:
            raise ValueError(f"Unexpected UMAP dimensions: {df.shape[1]}")

    # Add read index
    df['read_id'] = range(len(df))

    return df


def load_clusters(clusters_file: Path) -> pd.DataFrame:
    """
    Load cluster assignments.

    Args:
        clusters_file: Path to clusters file

    Returns:
        DataFrame with cluster assignments
    """
    # Try reading with header first (modern format from HDBSCAN output)
    df = pd.read_csv(clusters_file, sep='\t')

    # Check if cluster_id column exists (header format)
    if 'cluster_id' in df.columns:
        # Modern format with header - extract cluster_id column
        result = pd.DataFrame({
            'cluster_id': df['cluster_id'].astype(int),
            'read_id': range(len(df))
        })
    else:
        # Legacy format without header - single column
        df = pd.read_csv(clusters_file, sep='\t', header=None, names=['cluster_id'])
        result = pd.DataFrame({
            'cluster_id': df['cluster_id'].astype(int),
            'read_id': range(len(df))
        })

    return result


def load_abundances(abundances_file: Path) -> pd.DataFrame:
    """
    Load cluster abundances.

    Args:
        abundances_file: Path to abundances CSV

    Returns:
        DataFrame with abundances
    """
    df = pd.read_csv(abundances_file)
    # Ensure cluster_id is integer type for proper merging
    if 'cluster_id' in df.columns:
        df['cluster_id'] = df['cluster_id'].astype(int)
    return df


def load_annotations(annotations_file: Path) -> pd.DataFrame:
    """
    Load consensus annotations.

    Args:
        annotations_file: Path to annotations TSV

    Returns:
        DataFrame with annotations
    """
    return pd.read_csv(annotations_file, sep='\t')


def plot_umap_clustering(
    umap_df: pd.DataFrame,
    clusters_df: pd.DataFrame,
    abundances_df: pd.DataFrame,
    output_file: Path,
    title: str = "UMAP Clustering Visualization"
) -> None:
    """
    Create UMAP clustering visualization.

    Args:
        umap_df: UMAP coordinates
        clusters_df: Cluster assignments
        abundances_df: Cluster abundances
        output_file: Output PNG file
        title: Plot title
    """
    # Merge UMAP with clusters
    merged = umap_df.merge(clusters_df, on='read_id')

    # Merge with abundances to get taxon info
    # Note: Noise points (cluster_id = -1) won't be in abundances, will have NaN
    merged = merged.merge(
        abundances_df[['cluster_id', 'taxon', 'relative_abundance']],
        on='cluster_id',
        how='left'
    )

    # Fill NaN values for noise points
    merged['relative_abundance'] = merged['relative_abundance'].fillna(0.0)
    merged['taxon'] = merged['taxon'].fillna('Noise')

    # Create figure
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))

    # Plot 1: Colored by cluster
    unique_clusters = sorted(merged['cluster_id'].unique())
    colors = plt.cm.tab20(np.linspace(0, 1, len(unique_clusters)))

    for i, cluster_id in enumerate(unique_clusters):
        if cluster_id == -1:
            # Noise points in gray
            cluster_data = merged[merged['cluster_id'] == cluster_id]
            ax1.scatter(
                cluster_data['UMAP1'],
                cluster_data['UMAP2'],
                c='lightgray',
                s=10,
                alpha=0.3,
                label='Noise'
            )
        else:
            cluster_data = merged[merged['cluster_id'] == cluster_id]
            ax1.scatter(
                cluster_data['UMAP1'],
                cluster_data['UMAP2'],
                c=[colors[i]],
                s=30,
                alpha=0.6,
                label=f'Cluster {cluster_id}'
            )

    ax1.set_xlabel('UMAP 1', fontsize=12)
    ax1.set_ylabel('UMAP 2', fontsize=12)
    ax1.set_title('Colored by Cluster', fontsize=14, fontweight='bold')
    ax1.legend(bbox_to_anchor=(1.05, 1), loc='upper left', fontsize=8, ncol=2)
    ax1.grid(True, alpha=0.3)

    # Plot 2: Colored by abundance
    # Plot all points at once using their abundance values
    # Noise points have abundance=0, will be dark
    scatter = ax2.scatter(
        merged['UMAP1'],
        merged['UMAP2'],
        s=30,
        alpha=0.6,
        c=merged['relative_abundance'],  # Array of abundances, one per point
        cmap='viridis',
        vmin=0,
        vmax=merged['relative_abundance'].max()
    )

    ax2.set_xlabel('UMAP 1', fontsize=12)
    ax2.set_ylabel('UMAP 2', fontsize=12)
    ax2.set_title('Colored by Relative Abundance', fontsize=14, fontweight='bold')
    ax2.grid(True, alpha=0.3)

    # Add colorbar (use the scatter object directly)
    cbar = plt.colorbar(scatter, ax=ax2)
    cbar.set_label('Relative Abundance', fontsize=10)

    plt.suptitle(title, fontsize=16, fontweight='bold', y=1.02)
    plt.tight_layout()
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    plt.close()


def plot_abundance_distribution(
    abundances_df: pd.DataFrame,
    output_file: Path,
    title: str = "Cluster Abundance Distribution"
) -> None:
    """
    Create abundance distribution plots.

    Args:
        abundances_df: Cluster abundances
        output_file: Output PNG file
        title: Plot title
    """
    # Filter out noise cluster
    df = abundances_df[abundances_df['cluster_id'] != -1].copy()

    # Sort by abundance
    df = df.sort_values('relative_abundance', ascending=False)

    # Create figure with subplots
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))

    # Bar chart
    colors = plt.cm.viridis(np.linspace(0, 1, len(df)))
    bars = ax1.bar(range(len(df)), df['relative_abundance'] * 100, color=colors)

    ax1.set_xlabel('Cluster ID', fontsize=12)
    ax1.set_ylabel('Relative Abundance (%)', fontsize=12)
    ax1.set_title('Relative Abundance by Cluster', fontsize=14, fontweight='bold')
    ax1.set_xticks(range(len(df)))
    ax1.set_xticklabels(df['cluster_id'], rotation=45, ha='right')
    ax1.grid(True, axis='y', alpha=0.3)

    # Add value labels on bars
    for i, (bar, val) in enumerate(zip(bars, df['relative_abundance'] * 100)):
        if val > 1.0:  # Only label bars > 1%
            ax1.text(
                bar.get_x() + bar.get_width() / 2,
                bar.get_height(),
                f'{val:.1f}%',
                ha='center',
                va='bottom',
                fontsize=8
            )

    # Pie chart (top 10 + others)
    top_n = 10
    if len(df) > top_n:
        top_clusters = df.head(top_n)
        others_abundance = df.iloc[top_n:]['relative_abundance'].sum()

        pie_data = list(top_clusters['relative_abundance']) + [others_abundance]
        pie_labels = [f"Cluster {cid}" for cid in top_clusters['cluster_id']] + ['Others']
    else:
        pie_data = df['relative_abundance']
        pie_labels = [f"Cluster {cid}" for cid in df['cluster_id']]

    colors_pie = plt.cm.Set3(np.linspace(0, 1, len(pie_data)))

    wedges, texts, autotexts = ax2.pie(
        pie_data,
        labels=pie_labels,
        autopct='%1.1f%%',
        startangle=90,
        colors=colors_pie
    )

    # Improve text readability
    for text in texts:
        text.set_fontsize(10)
    for autotext in autotexts:
        autotext.set_color('white')
        autotext.set_fontsize(9)
        autotext.set_weight('bold')

    ax2.set_title('Abundance Distribution', fontsize=14, fontweight='bold')

    plt.suptitle(title, fontsize=16, fontweight='bold', y=1.02)
    plt.tight_layout()
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    plt.close()


def plot_taxonomy_composition(
    abundances_df: pd.DataFrame,
    annotations_df: pd.DataFrame,
    output_file: Path,
    title: str = "Taxonomic Composition"
) -> None:
    """
    Create taxonomic composition plot.

    Args:
        abundances_df: Cluster abundances
        annotations_df: Consensus annotations
        output_file: Output PNG file
        title: Plot title
    """
    # Abundances DataFrame already contains taxon information
    # No need to merge with annotations (would create taxon_x/taxon_y collision)
    # Aggregate by taxon directly
    taxon_abundances = abundances_df.groupby('taxon')['relative_abundance'].sum().sort_values(ascending=False)

    # Create figure
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))

    # Bar chart
    colors = plt.cm.tab20(np.linspace(0, 1, len(taxon_abundances)))
    bars = ax1.barh(range(len(taxon_abundances)), taxon_abundances * 100, color=colors)

    ax1.set_xlabel('Relative Abundance (%)', fontsize=12)
    ax1.set_ylabel('Taxon', fontsize=12)
    ax1.set_title('Taxonomic Abundance', fontsize=14, fontweight='bold')
    ax1.set_yticks(range(len(taxon_abundances)))

    # Truncate long taxon names
    labels = [
        name if len(name) <= 40 else name[:37] + '...'
        for name in taxon_abundances.index
    ]
    ax1.set_yticklabels(labels, fontsize=10)
    ax1.grid(True, axis='x', alpha=0.3)

    # Add value labels
    for i, (bar, val) in enumerate(zip(bars, taxon_abundances * 100)):
        ax1.text(
            bar.get_width(),
            bar.get_y() + bar.get_height() / 2,
            f' {val:.1f}%',
            ha='left',
            va='center',
            fontsize=9
        )

    # Pie chart (top 8 + others)
    top_n = 8
    if len(taxon_abundances) > top_n:
        top_taxa = taxon_abundances.head(top_n)
        others_abundance = taxon_abundances.iloc[top_n:].sum()

        pie_data = list(top_taxa) + [others_abundance]
        pie_labels = list(top_taxa.index) + ['Others']
    else:
        pie_data = taxon_abundances
        pie_labels = taxon_abundances.index

    # Truncate labels for pie chart
    pie_labels = [
        label if len(label) <= 30 else label[:27] + '...'
        for label in pie_labels
    ]

    colors_pie = plt.cm.Set3(np.linspace(0, 1, len(pie_data)))

    wedges, texts, autotexts = ax2.pie(
        pie_data,
        labels=pie_labels,
        autopct='%1.1f%%',
        startangle=90,
        colors=colors_pie
    )

    for text in texts:
        text.set_fontsize(9)
    for autotext in autotexts:
        autotext.set_color('white')
        autotext.set_fontsize(9)
        autotext.set_weight('bold')

    ax2.set_title('Taxonomic Distribution', fontsize=14, fontweight='bold')

    plt.suptitle(title, fontsize=16, fontweight='bold', y=1.02)
    plt.tight_layout()
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    plt.close()


def create_html_report(
    plot_files: List[Path],
    output_html: Path,
    sample_id: str,
    summary_data: Dict
) -> None:
    """
    Create HTML report combining all plots.

    Args:
        plot_files: List of plot PNG files
        output_html: Output HTML file
        sample_id: Sample identifier
        summary_data: Summary statistics
    """
    html_content = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NanoPulse Results - {sample_id}</title>
    <style>
        body {{
            font-family: Arial, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }}
        .header {{
            background-color: #2c3e50;
            color: white;
            padding: 20px;
            border-radius: 5px;
            margin-bottom: 20px;
        }}
        .summary {{
            background-color: white;
            padding: 20px;
            border-radius: 5px;
            margin-bottom: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        .plot {{
            background-color: white;
            padding: 20px;
            border-radius: 5px;
            margin-bottom: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        .plot img {{
            max-width: 100%;
            height: auto;
        }}
        h1 {{
            margin: 0;
        }}
        h2 {{
            color: #2c3e50;
            border-bottom: 2px solid #3498db;
            padding-bottom: 10px;
        }}
        .stat {{
            display: inline-block;
            margin: 10px 20px 10px 0;
        }}
        .stat-label {{
            font-weight: bold;
            color: #7f8c8d;
        }}
        .stat-value {{
            font-size: 24px;
            color: #2c3e50;
        }}
    </style>
</head>
<body>
    <div class="header">
        <h1>NanoPulse Analysis Results</h1>
        <p>Sample: {sample_id}</p>
    </div>

    <div class="summary">
        <h2>Summary Statistics</h2>
        <div class="stat">
            <div class="stat-label">Total Clusters</div>
            <div class="stat-value">{summary_data.get('total_clusters', 'N/A')}</div>
        </div>
        <div class="stat">
            <div class="stat-label">Total Reads</div>
            <div class="stat-value">{summary_data.get('total_reads', 'N/A'):,}</div>
        </div>
        <div class="stat">
            <div class="stat-label">Unique Taxa</div>
            <div class="stat-value">{summary_data.get('unique_taxa', 'N/A')}</div>
        </div>
        <div class="stat">
            <div class="stat-label">Shannon Diversity</div>
            <div class="stat-value">{summary_data.get('shannon', 'N/A'):.3f}</div>
        </div>
    </div>
"""

    # Add plots
    for plot_file in plot_files:
        plot_name = plot_file.stem.replace('_', ' ').title()
        html_content += f"""
    <div class="plot">
        <h2>{plot_name}</h2>
        <img src="{plot_file.name}" alt="{plot_name}">
    </div>
"""

    html_content += """
</body>
</html>
"""

    with open(output_html, 'w') as f:
        f.write(html_content)


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Create comprehensive visualizations for NanoPulse results"
    )

    parser.add_argument('--umap_vectors', type=Path, required=True, help='UMAP vectors file')
    parser.add_argument('--clusters', type=Path, required=True, help='Cluster assignments file')
    parser.add_argument('--abundances', type=Path, required=True, help='Abundances CSV file')
    parser.add_argument('--annotations', type=Path, required=True, help='Annotations TSV file')
    parser.add_argument('--output_prefix', type=str, required=True, help='Output file prefix')

    args = parser.parse_args()

    # Load data
    print("Loading data...")
    umap_df = load_umap_vectors(args.umap_vectors)
    clusters_df = load_clusters(args.clusters)
    abundances_df = load_abundances(args.abundances)
    annotations_df = load_annotations(args.annotations)

    # Create plots
    print("Creating UMAP clustering plot...")
    plot_umap_clustering(
        umap_df,
        clusters_df,
        abundances_df,
        Path(f"{args.output_prefix}_umap_clustering.png")
    )

    print("Creating abundance distribution plot...")
    plot_abundance_distribution(
        abundances_df,
        Path(f"{args.output_prefix}_abundance_distribution.png")
    )

    print("Creating taxonomy composition plot...")
    plot_taxonomy_composition(
        abundances_df,
        annotations_df,
        Path(f"{args.output_prefix}_taxonomy_composition.png")
    )

    # Collect plot files
    plot_files = [
        Path(f"{args.output_prefix}_umap_clustering.png"),
        Path(f"{args.output_prefix}_abundance_distribution.png"),
        Path(f"{args.output_prefix}_taxonomy_composition.png")
    ]

    # Create summary data
    # Convert all numpy types to Python native types for JSON serialization (Python 3.14 compatibility)
    summary_data = {
        'total_clusters': int(len(abundances_df)),
        'total_reads': int(abundances_df['read_count'].sum()),
        'unique_taxa': int(annotations_df['taxon'].nunique()),
        'shannon': float(0.0)  # Will be calculated if diversity metrics available
    }

    # Create HTML report
    print("Creating HTML report...")
    create_html_report(
        plot_files,
        Path(f"{args.output_prefix}_plots_report.html"),
        args.output_prefix,
        summary_data
    )

    # Create summary JSON
    summary_data['plots_generated'] = int(len(plot_files))
    summary_data['plot_files'] = [str(f) for f in plot_files]

    with open(f"{args.output_prefix}_plot_summary.json", 'w') as f:
        json.dump(summary_data, f, indent=2)

    print(f"Successfully generated {len(plot_files)} plots and HTML report")


if __name__ == '__main__':
    main()
