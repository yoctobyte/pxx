# Non-reproducible one-off miscompile (2026-06-02)

- **Type:** bug
- **Status:** blocked (can't reproduce; suspected hardware)
- **Owner:** —
- **Opened:** 2026-06-06 (from rainy-afternoon / anomaly report)

## Symptom

The *same* `compiler/pascal26` (md5 unchanged) occasionally produced a
*different*, crashing binary for `test/test_managed_record_exit.pas`. `cmp`
showed ~10 differing bytes at the same file size; analysis traced them to a
single corrupted value — the output image size `0x0fa9` → `0x401681` — propagated
to several emit sites (`mov %rsp, base+image-size` stored to the wrong address →
segfault).

## Why blocked

The toolchain uses no randomness, no timestamps, no intra-compile threads, and
the self-host gate requires byte-identical `build == verify` — output is
deterministic by construction. After the event a 400× determinism canary (200
self-compiles + 200 of the failing test) was byte-identical, zero crashes;
`bootstrap`/`test`/`test-nilpy` green. Never recurred. Leading suspicion:
transient hardware fault (RAM/cache bit flip on non-ECC memory), not a compiler
defect.

## If it recurs

Determinism canary: `for i in $(seq 1 200); do ./compiler/pascal26 test/hello.pas
/tmp/t; cmp /tmp/t /tmp/golden || echo "DIVERGED $i"; done`; plus
`journalctl -k | grep -iE 'mce|edac|hardware error'` and a memtest86 pass. Prefer
ECC RAM for long unattended self-host runs.

Full forensics: `../../developer/anomaly_2026-06-02_2000.md` (+ evidence dir).

## Log
- 2026-06-06 — ticket opened, parked in blocked/ (non-reproducible).
- 2026-06-19 — bug-hunt re-check: determinism canary byte-identical (60×
  `hello.pas` self-compiles, zero divergence), `make bootstrap` byte-identical,
  no `mce`/`edac`/hardware-error lines in `journalctl -k`. Still no code defect
  to fix; stays blocked (suspected transient hardware fault). The host remains
  non-ECC, so the recurrence/forensics guidance above still stands.
