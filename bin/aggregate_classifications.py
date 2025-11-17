#!/usr/bin/env python3
"""
Aggregate classification results from multiple clusters.

This script combines individual cluster classification JSON files into
a single aggregated JSON file for downstream analysis.

Usage:
    aggregate_classifications.py \\
        --input *.json \\
        --output aggregated_classifications.json
"""

import argparse
import json
import sys
from pathlib import Path


def parse_args():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Aggregate classification results from multiple clusters"
    )
    parser.add_argument(
        "--input",
        type=Path,
        nargs='+',
        required=True,
        help="Input classification JSON files"
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Output aggregated JSON file"
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print verbose output"
    )

    return parser.parse_args()


def load_classifications(json_files, verbose=False):
    """
    Load all classification JSON files.

    Parameters
    ----------
    json_files : list[Path]
        List of JSON file paths
    verbose : bool
        Print verbose output

    Returns
    -------
    list
        List of classification dictionaries
    """
    all_classifications = []

    for json_file in sorted(json_files):
        if verbose:
            print(f"Reading: {json_file}", file=sys.stderr)

        try:
            with open(json_file) as f:
                classification = json.load(f)
                all_classifications.append(classification)
        except json.JSONDecodeError as e:
            print(f"Warning: Failed to parse {json_file}: {e}", file=sys.stderr)
            continue
        except Exception as e:
            print(f"Warning: Failed to read {json_file}: {e}", file=sys.stderr)
            continue

    return all_classifications


def main():
    """Main execution function."""
    args = parse_args()

    if args.verbose:
        print(f"Aggregating {len(args.input)} classification files", file=sys.stderr)

    # Load all classifications
    all_classifications = load_classifications(args.input, args.verbose)

    if not all_classifications:
        print("Warning: No valid classification files found", file=sys.stderr)
        # Write empty list
        with open(args.output, 'w') as f:
            json.dump([], f, indent=2)
        return

    # Write aggregated JSON
    if args.verbose:
        print(f"Writing aggregated results to: {args.output}", file=sys.stderr)

    with open(args.output, 'w') as f:
        json.dump(all_classifications, f, indent=2)

    print(
        f"Successfully aggregated {len(all_classifications)} classification results",
        file=sys.stderr
    )


if __name__ == "__main__":
    main()
