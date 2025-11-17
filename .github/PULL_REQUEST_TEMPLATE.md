## PR checklist

- [ ] This comment contains a description of changes (with reason).
- [ ] Branch is up-to-date with the `dev` branch.
- [ ] Tests pass with `nf-test test --profile docker,test`.
- [ ] Pipeline runs successfully with test data.
- [ ] New code is documented and follows style guidelines.
- [ ] New features have corresponding tests.
- [ ] CLAUDE.md updated with any significant changes.

## Description

<!-- Please provide a brief description of your changes -->

## Related issues

<!-- If this PR addresses an issue, please link it here -->

Closes #

## Testing

<!-- Describe what testing you have performed -->

**Test command:**
```bash
nextflow run . -profile test,docker --outdir test_results
```

**Test results:**
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Real data validation (if applicable)
