---
description: "Use when adding, editing, or reviewing ComfyUI prompts in prompts.yaml. Enforces safe generation rules: all prompts must exclude minors and child-like subjects."
applyTo: "prompts.yaml"
---

# Safe Generation — Mandatory Prompt Rules

## Subject Age

Every prompt entry **must** satisfy both rules:

### Positive prompt must include at least one adult anchor tag:
- `adult` or `mature` or `young adult`
- OR explicit age descriptors: `20s`, `30s`, `adult woman`, `adult man`

### Negative prompt must include all of the following exclusion tags:
```
child, children, kid, kids, minor, minors, teen, teenager, underage,
loli, shota, childlike, young, juvenile, baby face, small stature,
school age, elementary, middle school
```

## Enforcement

When writing or modifying any prompt key:

1. **Check positive** — if no adult anchor is present, add `adult` before the subject tag (e.g. `adult, 1girl` not just `1girl`).
2. **Check negative** — if the minor-exclusion block is missing or incomplete, append it.
3. **Never omit** these tags to save space or simplify a prompt.
4. **Never use** ambiguous age descriptors like `young girl`, `young boy`, `petite`, `small` as positive tags without pairing them with an explicit `adult` anchor.

## Required Negative Block (copy-paste)

Add this block to every prompt's `negative` field:

```
child, children, kid, kids, minor, minors, teen, teenager, underage,
loli, shota, childlike, juvenile, baby face, school age
```

## Example — Correct

```yaml
illustrious_single_female:
  positive: >
    masterpiece, best quality, adult, 1girl, solo, ...
  negative: >
    worst quality, bad quality, ...,
    child, children, kid, kids, minor, minors, teen, teenager, underage,
    loli, shota, childlike, juvenile, baby face, school age
```

## Example — Incorrect (will be flagged)

```yaml
illustrious_single_female:
  positive: >
    masterpiece, best quality, 1girl, solo, ...   # MISSING adult anchor
  negative: >
    worst quality, bad quality, ...               # MISSING minor exclusion block
```
