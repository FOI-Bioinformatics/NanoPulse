# Testing Phase 2 Memory Optimizations

Quick reference guide for testing the three implemented optimizations.

---

## 1. Testing Sparse Matrix Output

### Test kmer_freq_streaming.py with sparse output

```bash
# Test TSV output only (backward compatible)
bin/kmer_freq_streaming.py \
  --reads test_datasets/mock4_run3bc08_5000.fastq \
  --kmer-size 9 \
  --threads 4 \
  --output-format tsv \
  | head -20

# Test NPZ sparse output only
bin/kmer_freq_streaming.py \
  --reads test_datasets/mock4_run3bc08_5000.fastq \
  --kmer-size 9 \
  --threads 4 \
  --output-format npz \
  --output-prefix test_kmer_sparse

# Check generated files
ls -lh test_kmer_sparse*
# Expected: test_kmer_sparse.npz + test_kmer_sparse_metadata.npz

# Test both formats (default)
bin/kmer_freq_streaming.py \
  --reads test_datasets/mock4_run3bc08_5000.fastq \
  --kmer-size 9 \
  --threads 4 \
  --output-format both \
  --output-prefix test_kmer_both \
  > test_kmer_both.tsv

# Verify both outputs created
ls -lh test_kmer_both*
# Expected: test_kmer_both.tsv, test_kmer_both.npz, test_kmer_both_metadata.npz
```

### Test umap_reduce.py with sparse input

```bash
# First, create sparse k-mer matrix
bin/kmer_freq_streaming.py \
  --reads test_datasets/mock4_run3bc08_5000.fastq \
  --kmer-size 9 \
  --threads 4 \
  --output-format npz \
  --output-prefix test_sparse

# Test UMAP with sparse input
bin/umap_reduce.py \
  --input test_sparse.npz \
  --output test_umap_from_sparse.tsv \
  --plot test_umap_sparse.png \
  --n-components 3 \
  --n-neighbors 15 \
  --min-dist 0.1 \
  --low-memory \
  --verbose

# Compare with TSV input
bin/kmer_freq_streaming.py \
  --reads test_datasets/mock4_run3bc08_5000.fastq \
  --kmer-size 9 \
  --threads 4 \
  > test_dense.tsv

bin/umap_reduce.py \
  --input test_dense.tsv \
  --output test_umap_from_dense.tsv \
  --plot test_umap_dense.png \
  --n-components 3 \
  --verbose

# Results should be nearly identical (minor numeric differences due to random initialization)
diff test_umap_from_sparse.tsv test_umap_from_dense.tsv
```

---

## 2. Testing PCA Preprocessing

### Test PCA with TSV input

```bash
# Generate k-mer frequencies
bin/kmer_freq_streaming.py \
  --reads test_datasets/mock4_run3bc08_5000.fastq \
  --kmer-size 9 \
  --threads 4 \
  | gzip > test_kmer_freqs.txt.gz

# Run PCA preprocessing
bin/pca_preprocess.py \
  --input test_kmer_freqs.txt.gz \
  --output test_pca_features.tsv \
  --variance-report test_variance.json \
  --n-components 50 \
  --min-variance 0.99 \
  --verbose

# Check variance report
cat test_variance.json | python -m json.tool

# Expected output:
# - total_variance_explained: >0.99
# - meets_minimum_variance: true
# - memory_reduction_factor: ~2621 (131072 / 50)

# Verify output format
head -10 test_pca_features.tsv
# Expected columns: read, length, PC1, PC2, ..., PC50
```

### Test PCA with sparse input

```bash
# Generate sparse k-mer matrix
bin/kmer_freq_streaming.py \
  --reads test_datasets/mock4_run3bc08_5000.fastq \
  --kmer-size 9 \
  --threads 4 \
  --output-format npz \
  --output-prefix test_kmer_sparse

# Run PCA on sparse input
bin/pca_preprocess.py \
  --input test_kmer_sparse.npz \
  --output test_pca_from_sparse.tsv \
  --variance-report test_variance_sparse.json \
  --n-components 50 \
  --verbose

# Should show "Loaded sparse matrix" and conversion to dense
# Results should be identical to TSV input
```

### Test PCA → UMAP pipeline

```bash
# Full pipeline test
bin/kmer_freq_streaming.py \
  --reads test_datasets/mock4_run3bc08_5000.fastq \
  --kmer-size 9 \
  --threads 4 \
  | gzip > kmer_freqs.txt.gz

bin/pca_preprocess.py \
  --input kmer_freqs.txt.gz \
  --output pca_features.tsv \
  --n-components 50 \
  --verbose

bin/umap_reduce.py \
  --input pca_features.tsv \
  --output umap_coords.tsv \
  --plot umap_plot.png \
  --n-components 3 \
  --verbose

# Check final output
head umap_coords.tsv
# Should show 3D UMAP coordinates from 50 PCA features
```

---

## 3. Testing PaCMAP Alternative

### Test PaCMAP with TSV input

```bash
# Generate k-mer frequencies
bin/kmer_freq_streaming.py \
  --reads test_datasets/mock4_run3bc08_5000.fastq \
  --kmer-size 9 \
  --threads 4 \
  | gzip > test_kmer_freqs.txt.gz

# Run PaCMAP
bin/pacmap_reduce.py \
  --input test_kmer_freqs.txt.gz \
  --output test_pacmap_coords.tsv \
  --plot test_pacmap_plot.png \
  --n-components 3 \
  --n-neighbors 15 \
  --verbose

# Verify output format matches UMAP
head test_pacmap_coords.tsv
# Expected columns: read, length, UMAP1, UMAP2, UMAP3
# (note: columns named UMAP for compatibility)
```

### Compare UMAP vs PaCMAP speed

```bash
# Time UMAP
time bin/umap_reduce.py \
  --input test_kmer_freqs.txt.gz \
  --output test_umap.tsv \
  --plot test_umap.png \
  --n-components 3 \
  --verbose

# Time PaCMAP
time bin/pacmap_reduce.py \
  --input test_kmer_freqs.txt.gz \
  --output test_pacmap.tsv \
  --plot test_pacmap.png \
  --n-components 3 \
  --verbose

# PaCMAP should be 2-3x faster
```

### Test PCA → PaCMAP pipeline

```bash
# Full pipeline with PaCMAP
bin/kmer_freq_streaming.py \
  --reads test_datasets/mock4_run3bc08_5000.fastq \
  --kmer-size 9 \
  --threads 4 \
  --output-format npz \
  --output-prefix sparse_kmer

bin/pca_preprocess.py \
  --input sparse_kmer.npz \
  --output pca_features.tsv \
  --n-components 50 \
  --verbose

bin/pacmap_reduce.py \
  --input pca_features.tsv \
  --output pacmap_coords.tsv \
  --plot pacmap_plot.png \
  --n-components 3 \
  --verbose

# Optimal pipeline: sparse + PCA + PaCMAP
# Should be fastest and most memory efficient
```

---

## 4. Memory Usage Monitoring

### Monitor memory during processing

```bash
# Install psutil if needed
pip install psutil

# Create monitoring script
cat > monitor_memory.py << 'EOF'
#!/usr/bin/env python3
import psutil
import sys
import time

while True:
    mem = psutil.virtual_memory()
    print(f"Memory: {mem.percent:.1f}% ({mem.used / 1024**3:.2f} GB / {mem.total / 1024**3:.2f} GB)", file=sys.stderr)
    time.sleep(2)
EOF
chmod +x monitor_memory.py

# Run in background while testing
./monitor_memory.py &
MONITOR_PID=$!

# Run your test
bin/pca_preprocess.py --input large_dataset.txt.gz --output pca.tsv

# Stop monitoring
kill $MONITOR_PID
```

---

## 5. Validation Checklist

### Sparse Matrix Infrastructure
- [ ] TSV output works (backward compatible)
- [ ] NPZ sparse output created
- [ ] Metadata file created alongside NPZ
- [ ] UMAP can load NPZ files
- [ ] Sparse vs dense results are nearly identical
- [ ] File size reduction ~90%

### PCA Preprocessing
- [ ] Works with TSV input
- [ ] Works with NPZ sparse input
- [ ] Variance report shows >99% preservation
- [ ] Output has 50 features (or specified n_components)
- [ ] Can be fed to UMAP/PaCMAP
- [ ] Memory reduction ~95%

### PaCMAP Alternative
- [ ] Works with TSV input
- [ ] Works with NPZ sparse input
- [ ] Output format matches UMAP
- [ ] Column names are UMAP1, UMAP2, UMAP3
- [ ] 2-3x faster than UMAP
- [ ] Drop-in replacement verified

---

## 6. Expected Performance Metrics

### Small Dataset (5,000 reads)
- K-mer calculation: <1 minute
- PCA (131k → 50): <30 seconds
- UMAP (50 features): <1 minute
- PaCMAP (50 features): <30 seconds
- **Total pipeline: ~3 minutes**

### Medium Dataset (50,000 reads)
- K-mer calculation: ~5 minutes
- PCA (131k → 50): ~5 minutes
- UMAP (50 features): ~10 minutes
- PaCMAP (50 features): ~3-5 minutes
- **Total pipeline: ~20-30 minutes**

### Large Dataset (100,000 reads)
- K-mer calculation: ~10 minutes
- PCA (131k → 50): ~15 minutes
- UMAP (50 features): ~30 minutes
- PaCMAP (50 features): ~10-15 minutes
- **Total pipeline: ~1-1.5 hours**

### Memory Usage (100k reads)
- Without optimizations: ~525 GB
- Sparse only: ~53 GB
- Sparse + PCA: ~13 GB
- Sparse + PCA + PaCMAP: ~5-8 GB

---

## 7. Troubleshooting

### Sparse matrix errors
**Problem**: "cannot load npz file"
**Solution**: Ensure both .npz and _metadata.npz files exist

**Problem**: "out of memory during sparse conversion"
**Solution**: Use smaller dataset or increase swap space

### PCA errors
**Problem**: "variance below threshold"
**Solution**: Increase n_components or decrease min_variance

**Problem**: "temporary memory spike"
**Solution**: Expected - PCA needs to load full matrix momentarily

### PaCMAP errors
**Problem**: "pacmap module not found"
**Solution**: Install with `conda install -c conda-forge pacmap`

**Problem**: "slower than expected"
**Solution**: Ensure running on PCA-reduced features, not full k-mer matrix

---

## 8. Quick Test Script

Save this as `test_phase2_all.sh`:

```bash
#!/bin/bash
set -e

echo "Testing Phase 2 Memory Optimizations..."
echo "========================================"

READS="test_datasets/mock4_run3bc08_5000.fastq"
KMER_SIZE=9
THREADS=4

echo ""
echo "1. Testing sparse matrix generation..."
bin/kmer_freq_streaming.py \
  --reads $READS \
  --kmer-size $KMER_SIZE \
  --threads $THREADS \
  --output-format both \
  --output-prefix test_sparse \
  > test_sparse.tsv
echo "   ✓ Sparse matrix created"

echo ""
echo "2. Testing PCA preprocessing..."
bin/pca_preprocess.py \
  --input test_sparse.npz \
  --output test_pca.tsv \
  --n-components 50 \
  --verbose
echo "   ✓ PCA completed"

echo ""
echo "3. Testing PaCMAP dimensionality reduction..."
bin/pacmap_reduce.py \
  --input test_pca.tsv \
  --output test_pacmap.tsv \
  --plot test_pacmap.png \
  --n-components 3 \
  --verbose
echo "   ✓ PaCMAP completed"

echo ""
echo "4. Testing UMAP with sparse input..."
bin/umap_reduce.py \
  --input test_sparse.npz \
  --output test_umap_sparse.tsv \
  --plot test_umap_sparse.png \
  --n-components 3 \
  --low-memory \
  --verbose
echo "   ✓ UMAP completed"

echo ""
echo "========================================"
echo "All Phase 2 optimizations tested successfully!"
echo "Generated files:"
ls -lh test_sparse* test_pca* test_pacmap* test_umap_sparse* 2>/dev/null || true
```

Run with:
```bash
chmod +x test_phase2_all.sh
./test_phase2_all.sh
```

---

## Summary

All three optimizations can be tested independently:

1. **Sparse matrices**: Test with real data, verify file size reduction
2. **PCA preprocessing**: Verify variance preservation, check JSON report
3. **PaCMAP alternative**: Compare speed vs UMAP, verify output compatibility

The full pipeline (sparse + PCA + PaCMAP) provides maximum memory efficiency and speed.

**Next step**: Choose integration strategy and request workflow modification.
