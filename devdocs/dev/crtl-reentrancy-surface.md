# crtl's reentrancy surface — what is shared, and which sharing is a defect

Measured 2026-09-19 (frankS), at `607d490a8`. **Re-runnable: every command is
below.** Written because the census existed only in a peer message, which is
the same failure mode as a finding that only exists in a context window.

**Read the classification, not the count.** A census of `static` in a C library
produces a large and frightening number that is mostly the C standard working
as designed. The number that matters here is six.

## Why this exists

`errno` was one process-wide `int` shared by every thread until 2026-09-19
(`c5ae069c5`). Once it became `__thread`, the obvious question is what ELSE in
crtl is one object where a threaded program needs one per thread. Threaded C on
pxx genuinely runs now — `lib/crtl/src/pthread.c` routes `pthread_create`
through `PxxPthreadStart`, which installs a real per-thread TLS block — so this
stopped being theoretical.

## The instrument

    # file-scope static, non-const, non-function -- the classic racy shape
    for f in lib/crtl/src/*.c; do
      n=$(awk '/^static / && !/const/ && !/\(/ {c++} END{print c+0}' "$f")
      [ "$n" -gt 0 ] && printf "%4d  %s\n" "$n" "$(basename $f)"
    done | sort -rn

    # and to list them rather than count them
    for f in lib/crtl/src/*.c; do
      awk -v F="$(basename $f)" '/^static / && !/const/ && !/\(/ {printf "  %-12s %s\n", F, $0}' "$f"
    done

**A FIRST ATTEMPT AT THIS WAS GARBAGE AND IS RECORDED SO NOBODY REPEATS IT.** A
looser regex meant to catch any file-scope definition reported **163 objects in
`stdio.c` alone** — it was matching function prototypes and `extern`
declarations. Every number in this document comes from the narrow `^static`
form above. If you widen it, re-derive the classification too; the wide count
is not this count with more rows, it is a different question.

## Result: 46 objects across 15 of 32 modules

    5  syslog.c    5  stdio.c     5  netdb.c    4  time.c     4  stdlib.c
    4  grp.c       3  unistd.c    3  string.c   3  pwd.c      2  resolv.c
    2  pthread.c   2  mntent.c    2  libgen.c   1  signal.c   1  locale.c

## Classification — this is the part that matters

### 1. POSIX-sanctioned non-reentrant (the majority, NOT defects)

The standard explicitly permits `strtok`, `asctime`, `ctime`, `gmtime`,
`localtime`, `rand`, `strerror`, `strsignal`, the `getpw*`/`getgr*`/`getserv*`
families, `getmntent`, `setlocale` and `getopt` to keep static state. The
remedy the standard itself specifies is the `_r` variant. **Where the `_r`
exists, the plain one racing is the documented contract and not our bug.**

Present when censused: `strtok_r`, `strerror_r`, `asctime_r`, `ctime_r`,
`gmtime_r`, `localtime_r`.

### 2. Absent reentrant variants — the real finding, and it was six

`rand_r`, `getpwnam_r`, `getpwuid_r`, `getgrnam_r`, `getgrgid_r`,
`getservbyname_r` had **no definition in `lib/crtl/src` and no declaration in
`lib/crtl/include`**. That is a different and worse class than the row above:
the plain call races and the reentrant spelling will not link, so a threaded C
program has **no correct call available and cannot work around us**.

**All six were implemented the same day** (this document's own commit). Check
before quoting this section as an open gap:

    for n in rand_r getpwnam_r getpwuid_r getgrnam_r getgrgid_r getservbyname_r; do
      printf "  %-18s def=%-24s decl=%s\n" "$n" \
        "$(grep -rl "\b$n\b" lib/crtl/src/ | head -1)" \
        "$(grep -rl "\b$n\b" lib/crtl/include/ | head -1)"
    done

### 3. Correctly process-wide (not defects, do not "fix")

`environ` (`pxx_env_buf` in `stdlib.c`), the TZ cache (`time.c`), the installed
signal dispositions (`__pxx_prev` in `signal.c`), and `pthread.c`'s thread
registry — which already carries its own mutex. A process has one environment
and one signal disposition table; per-thread copies would be wrong.

### 4. Shared TABLES with no guard — a separate class, open

`__crtl_files[16]` and `pxx_popens[16]` in `stdio.c`. These are not the POSIX
allowance and not correctly-process-wide: they are shared resources allocated
by an unguarded test-then-set. Filed as
`decide-crtl-s-FILE-table-is-an-unguarded-test-then-set-and-no-probe-has-caught-it`,
with both failed probes recorded in it. **The mechanism is clear and no probe
has caught it** — do not read the open ticket as a demonstrated race, and read
its "do not re-probe this" section before writing a third one.

## What this census does NOT answer

It enumerates file-scope `static`. It cannot see state reached through a
pointer, state in `lib/rtl` that crtl calls into, or a function that is
non-reentrant for a reason other than storage. **Print the set your instrument
enumerates and check your subject is in it** — that rule is why the six were
found and why the 163 was caught.
