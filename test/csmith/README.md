# csmith reproducers for OPEN bugs

Generated C programs that a pxx build gets wrong and gcc gets right, kept
verbatim because **a seed alone cannot prove a fix**
(`bug-t-a-fuzz-finding-cited-by-seed-alone-cannot-prove-a-fix`): a seed only
reproduces against an identical csmith version AND identical generator args, so
a finding cited by seed is unverifiable the moment either moves. The program is
the evidence; the seed is only how it was found.

**Nothing here is wired into a make target.** These reproduce OPEN bugs, so a
recipe would be a permanent red. Wire one in — beside the other C recipes in
`test-core` — as part of the commit that FIXES it, and move the file out of this
directory at the same time.

## Running one by hand

```
gcc -w -I/usr/include/csmith -o /tmp/oracle test/csmith/<file>.c && /tmp/oracle
./compiler/pascal26 -I/usr/include/csmith -Ilib/crtl/include -Ilib/crtl/src \
    test/csmith/<file>.c /tmp/got && timeout 20 /tmp/got
```

The csmith headers come from the distro `csmith` package (`/usr/include/csmith`),
not from this repo — third-party source is never vendored here.

## Contents

| file | bug | symptom |
| --- | --- | --- |
| `hang_builtins_700082.c` | `bug-a-a-csmith-program-hangs-under-pxx-at-every-o-level-and-runs-under-gcc` | infinite loop in `func_58`; gcc prints `checksum = 5ABA20EA` |
