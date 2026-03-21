## Description

<!-- Describe what this PR does and why. Link to related issues with "Closes #NNN". -->

## Type of Change

<!-- Check all that apply -->

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to change)
- [ ] Documentation update
- [ ] Test improvement
- [ ] Refactor (no functional change)

## Changes Made

<!-- Bullet-point summary of what changed -->

-
-
-

## Testing

<!-- Describe how you tested your changes -->

**Test commands run:**

```bash
make test        # Full suite
make lint        # ShellCheck
```

**New tests added:**

- [ ] Yes — describe below
- [ ] No — explain why not

<!-- If new tests were added, list them -->

**Manual testing performed:**

<!-- Describe any manual testing beyond BATS (e.g., real socat with --capture, dual-stack stop) -->

## Checklist

<!-- All items must be checked before merge -->

### Code Quality
- [ ] `make lint` passes (ShellCheck, no warnings)
- [ ] `make test` passes (all BATS tests, currently 143+)
- [ ] No existing tests broken by this change
- [ ] No existing functionality removed or degraded

### Documentation (if applicable)
- [ ] Function documentation headers added/updated (Description, Parameters, Returns)
- [ ] Inline comments explain non-obvious logic
- [ ] Help text updated for new/changed CLI flags (`show_*_help` functions)
- [ ] Main help updated if the flag is global (`show_main_help`)

### Project Files (if applicable)
- [ ] CHANGELOG.md updated under `[Unreleased]` section
- [ ] README.md updated (options tables, examples) for new features
- [ ] USAGE_GUIDE.md updated for significant changes

### Security (if applicable)
- [ ] All user inputs pass through `validate_*` functions
- [ ] No raw user input interpolated into command strings
- [ ] File permissions set correctly (session files 600, keys 600, dirs 700)
- [ ] No sensitive data written to logs

## Screenshots / Output

<!-- If applicable, paste relevant console output or screenshots -->

<details>
<summary>Console output (click to expand)</summary>

```
# Paste output here
```

</details>

