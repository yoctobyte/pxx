---
track: N
prio: 55
type: feature
---

# `import glob` — there was no glob module

Found missing 2026-10-19 in sysdash's backend.py
(`cpu[0-9]*/cpufreq/scaling_cur_freq`, `hwmon*`, `temp*_label`).

**Fix:** lib/rtl/mimic_glob.py, a plain-Python shim over os.listdir. It has
glob, iglob (which returns a list), escape and has_magic, and supports
fnmatch's `* ? [seq] [!seq]` with ranges and `**` with recursive=True. Hidden
names, a final `**` that also yields files, and a pattern with no magic all
behave as in CPython. root_dir=, dir_fd= and include_hidden= are not
implemented. It has no fnmatch module of its own yet; the matcher lives inside
glob.

**Test:** test/test_nilpy_glob_module.npy builds its own tree under /tmp.
