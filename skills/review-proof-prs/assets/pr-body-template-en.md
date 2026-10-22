### Problem

<What's wrong and why, stated as a self-contradiction (path A does X; sibling/spec requires X; path B doesn't). Point to the sibling code path by file and line to show the project already handles this class correctly elsewhere. Quote the offending code if it helps.>

### Repro (before fix)

<Reproducible steps a reviewer can run, on the real usage path. Show real output demonstrating the wrong behavior — not a summary.>

```
<real output>
```

### Fix

<The minimal change bringing the path in line with the spec/sibling.>

```diff
- <as-is>
+ <to-be>
```

### Test

<A test that fails on old code and passes with the fix. Confirm it actually fails without the fix (remove the fix → RED). Include the full suite result.>

### Note on behavior change

<Honest disclosure of any behavior change and exactly who it affects. If nothing user-visible changes except the bug, say so.>

---
<AI-assistance disclosure if that is the project's norm. Run the finalized prose through the humanizer skill before opening the PR.>
