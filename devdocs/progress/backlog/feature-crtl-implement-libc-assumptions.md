---
prio: 10  # standing collector: rank the batch you file, not this
---

# crtl: implement the libc assumptions real-world C leans on

- **Type:** feature (libraries) — Track B (`lib/crtl`).
- **Status:** backlog, ongoing collector — 2026-07-06.
- **Premise (user, 2026-07-06):** gcc has its own libc; we have our own
  (`lib/crtl`, libc-free). Real C leans on a *waspnest of libc assumptions* —
  headers, macros, feature-test knobs, struct layouts, function contracts. Bring
  our crtl up to those assumptions incrementally, driven by what real projects
  actually touch. Don't chase completeness for its own sake — implement what the
  corpus (zlib → tcc → …) demands, one landed piece at a time.

## Why a standing ticket
Each real-world bring-up ([[feature-c-corpus-zlib]], tcc next) surfaces a fresh
batch of "libc assumed X" gaps. Rather than a ticket per tiny gap, collect them
here; split a dedicated ticket out only when a gap is large or blocks a whole
project. Distinguish: a **compiler/parser** gap is Track C (own ticket); a
**library surface** gap (missing header symbol, wrong macro, absent function) is
this ticket / Track B.

## Known / expected assumption classes (fill in as found)
- Header symbols declared-but-unimplemented (functions real code calls).
- Feature-test macros & config (`STDC`, `_LARGEFILE64_SOURCE`, `Z_HAVE_UNISTD_H`
  style probes) that gate which code path a project compiles.
- Struct layouts C code reaches into (stat, FILE internals, off_t width).
- `<limits.h>` / `<stdint.h>` / `<inttypes.h>` completeness (widths, INT*_MAX,
  format-length macros).
- errno values + names; `<ctype.h>` locale assumptions; math edge functions.
- (zlib specifically will want: correct `<unistd.h>`/`<fcntl.h>` for gzio file
  I/O, `off_t`/`lseek`, and whatever the gzgetc fast-path macro assumes.)

## How to work it
Bring up a real project → when it fails on a *library* symbol/assumption (not a
parser bug), add the concrete gap here with the project + call site, implement
the smallest crtl piece that satisfies it, land green (`make lib-test`), tick it
off. Keep gcc's libc as the oracle for behaviour.

## Gate
Per-item: the crtl addition compiles + the consuming project advances; `make
lib-test` stays green. Ongoing ticket — never "done", pruned as the corpus grows.

## Collected gap: `<inttypes.h>` (2026-07-20, Track B — CLOSED)

**Was:** 15 PRI macros and **zero SCN macros**, so any `scanf("%" SCNd64, &v)`
failed — and failed confusingly, because a missing PRI/SCN macro is not an error
at its definition, it is an undefined identifier inside string concatenation,
which surfaces as a syntax error some distance from the cause. Also declared
`strtoimax`/`strtoumax` with **no implementation anywhere in `lib/crtl/src`** —
exactly the "declared-but-unimplemented" category this ticket lists first.

**Now:** the full C99 set — PRI and SCN, for d/i/u/o/x/X, across
8/16/32/64/LEAST/FAST/PTR/MAX — plus `imaxdiv_t`, `imaxabs`, `imaxdiv`, and real
bodies for `strtoimax`/`strtoumax` in `lib/crtl/src/stdlib.c`.

**The part worth remembering:** the first draft was written from glibc's table
and was WRONG in two groups, because our `<stdint.h>` is not glibc's:

| type | glibc LP64 | ours | consequence |
| --- | --- | --- | --- |
| `intmax_t` | `long` | `long long` | MAX group is `"ll*"`, not `"l*"` |
| `int_fast16_t` / `int_fast32_t` | `long` | `long` | FAST16/32 are `"l*"`, not plain |
| `int64_t` | `long` | `long long` | 64-bit group is `"ll*"` |

None of these warn at the call site — they are varargs, so a wrong modifier
reads the wrong number of bytes off the stack and prints garbage. The header now
says this at the top so the next editor re-derives rather than assumes.

Gated by `test/crtl_inttypes.c` in `make lib-test` (exit 42 on success, like the
other `crtl_*.c` tests). It is deliberately **printf-free**: a wrong length
modifier IS a varargs bug, so a printf-based check would be testing the bug with
the bug — it compares the macro strings instead. Note gcc returns 1, not 42, on
this file and must not be "fixed" to agree: it asserts our ABI, and only the
8/16/32-bit and LEAST groups are common ground with glibc.

### Separate finding, NOT fixed here

Any crtl C program that calls `printf` dies at runtime under the current pin:

```
/tmp/p: symbol lookup error: /tmp/p: undefined symbol: __pxx_fegetround
```

Reproduces with a bare `printf("hi %d\n", 42)`, so it is nothing to do with
inttypes. `__pxx_fegetround` is registered by `compiler/cparser.inc` (~line 7148),
so this is pin lag — the pinned v222 predates it — not a live defect in HEAD.
Worth confirming after the next `make pin`; it is also why the existing
`crtl_*.c` tests are all exit-code based rather than printing anything.

## Declared-but-unimplemented sweep (2026-07-20, Track B)

Ran the ticket's own first category as an actual sweep rather than waiting for
the next project to trip over it: every `extern` function declared in
`lib/crtl/include/**` checked for a definition in `lib/crtl/src/**`, then each
survivor probed by taking its address, linking, and running.

**107 declared, 23 with no visible definition, exactly 1 real gap.** The other 22
resolve and were noise in the static check, worth recording so nobody re-chases
them:

- `__pxx_fegetround` / `__pxx_fesetround` / `__pxx_setjmp` / `__pxx_longjmp` —
  registered by the compiler (`cparser.inc`), not library symbols.
- `ceil floor fmod sqrt hypot log2 log10 cosh sinh tanh cos sin tan` — bind to
  Pascal RTL routines, or reach `__crtl_*` through the math.h macros.
- `ioctl mremap msync chmod umask` — all link and run.

**The one real gap: `exp2`.** Declared in `<math.h>`, defined nowhere. A C
program calling it compiled, linked, and then died at run time with
`undefined symbol: exp2` — the worst-behaved shape in this category, because
nothing catches it until the program is already running.

Implemented as `exp(x * ln2)` with ln2 carried as a double-double, so the
product keeps its low bits rather than losing them to a rounding before the
exponential (which is where a naive `exp(x * M_LN2)` drifts for large |x|).
Exact powers of two return `ldexp` directly — `2^k` must be *exact* for integral
k, and routing those through the series would round. Judged against 120-digit
references: 16 cases, all correctly rounded, 0 ulp. Gated as
`test/crtl_exp2.c` in `make lib-test`.

## Standing-collector note

This ticket is an **ongoing collector by design** — its own status line says so —
so it does not have a "done" state and should not sit in the ready queue as if it
did. The currently-collected batch (inttypes completeness + this sweep) is
closed. File the next batch against it when a project trips over something; the
sweep above is cheap to re-run and worth repeating after any header change.


## Collected sweep: declared-but-unimplemented census + a gcc DIFFERENTIAL (2026-07-31, Track B)

The first assumption class this ticket lists is "header symbols
declared-but-unimplemented (functions real code calls)". Swept it.

**A textual census of `lib/crtl/include/**.h` against `lib/crtl/src` suggested 58
missing symbols. Empirically, 36 of the plausible ones all compile and link.**
The census was mostly false positives — bodies live in places a regex over
`src/` does not see. Worth recording because the next person will run the same
grep and reach the same wrong conclusion: **link-probe the candidates, do not
grep for definitions.**

### What replaced the census: an oracle test

Linking is not agreement, and this ticket already says gcc's libc is the oracle
for behaviour — but nothing gated that. `test/crtl_libc_oracle.c` now does, and
it is in `lib-test`: **the same file is built by gcc and by pxx and the entire
output is diffed**, so there are no recorded expectations to drift. A recorded
expectation for a libc surface is just our own behaviour written down.

The batch, chosen as the places a wrong answer would be silent:

- `strtoll` / `strtoull` — base 10/16/0, leading space, sign, `endptr`
  placement, the max values, the overflow clamp, and `strtoull("-1")` (which is
  `ULLONG_MAX`, not an error).
- `atoll` / `atof` with trailing garbage.
- The whole wide-ctype family — 12 `isw*` predicates on deliberately awkward
  inputs (`iswgraph(L' ')`, `iswprint(L'\t')`, `iswspace(L'\v')`), plus
  `towlower`/`towupper` including the no-op case, and `wcslen`.
- Math edges where sign and rounding are the interesting part: `fmod` with each
  sign combination, `hypot`, `log2` below 1, `exp2` negative, `sinh`/`cosh`/
  `tanh`, `fabsf`, and `ceil`/`floor` on both signs.
- `bsearch` hit AND miss.
- A `PRId64` -> `sscanf("%" SCNd64)` round trip — because a wrong length
  modifier is varargs, so it reads the wrong bytes off the stack with no
  diagnostic anywhere. (That is exactly how the `<inttypes.h>` item above went
  wrong the first time.)

**Result: 25 lines, byte-identical to gcc.** No gap to close in this batch — the
value landed is the gate, not a fix.

### One real bug found on the way

The first draft used a GNU nested function as the `bsearch` comparator. pxx
warned "undeclared identifier 'cmp' used as value (treated as 0)", built the
program anyway, and it **segfaulted calling through null**. Filed as
[[bug-c-undeclared-identifier-as-function-pointer-becomes-null]] (Track C).
Nested functions are an extension and not supporting them is defensible; turning
an undeclared identifier into a null callback and building it is not. Same
"treated as 0" recovery that silently made `M_SQRT2` zero in
[[bug-crtl-headers-lost-when-cwd-is-not-the-repo-root]].

## Collected gap: `<errno.h>` was missing 39 of 71 names (2026-07-31, Track B — CLOSED)

Second oracle batch, over the assumption classes this ticket lists: widths,
`<limits.h>`/`<stdint.h>` completeness, struct layouts, and errno.

**Was:** 36 errno names. A census against the set real code uses found **39 of
71 missing**, including the ENTIRE socket family — `ECONNREFUSED`,
`ECONNRESET`, `EINPROGRESS`, `EADDRINUSE`, `EHOSTUNREACH`, `ENOTCONN` … — plus
`EDOM`, `EILSEQ`, `ENAMETOOLONG`, `ELOOP`, `ENOSYS`, `EWOULDBLOCK`, `ENOTSUP`.

**Why missing is worse than wrong here.** An undeclared identifier in C is
"treated as 0" with only a warning, so

```c
if (errno == ECONNREFUSED) { ... }   /* compiled to  errno == 0  */
```

— and `0` is the SUCCESS value. The branch fired exactly when it should not
have, on every net-facing path, with a warning that scrolls past in a build log.
That is the same "treated as 0" recovery that silently made `M_SQRT2` zero
([[bug-crtl-headers-lost-when-cwd-is-not-the-repo-root]]) and that builds a null
callback ([[bug-c-undeclared-identifier-as-function-pointer-becomes-null]]).
Three separate victims of one recovery rule; it is worth revisiting on its own.

**Now:** all 71, every value printed by a gcc-built program on this target
rather than copied from documentation — these numbers are an ABI. Both glibc
aliases are kept (`EWOULDBLOCK == EAGAIN`, `ENOTSUP == EOPNOTSUPP`) and the
header says so at the declaration.

**Gated:** `test/crtl_libc_oracle.c` grew the full errno set plus the widths and
limits (`sizeof` for every integer type, `CHAR_BIT`, plain-`char` signedness,
the INT/LONG/LLONG/INT64/SIZE_MAX bounds). 40 lines, byte-identical to gcc.

### Recorded, NOT a bug: `struct stat` has a different layout

`sizeof(struct stat)` is 96 here and 144 under glibc, with `st_mode` at offset
16 rather than 24. Checked before concluding: our `stat()` fills OUR layout
correctly — size, `S_ISREG`, `S_ISDIR` and the permission bits all match gcc on
the same files, and a guard buffer around the struct is untouched, so nothing is
being handed to the kernel short. It is a self-consistent divergence, not a
smash. It matters only to C that hard-codes offsets or moves the struct across
an ABI boundary; the layout numbers are deliberately NOT in the oracle test,
since they would fail for a benign reason.

## Collected gap: `strnlen` absent (2026-07-31, Track B — CLOSED)

Third oracle batch, over `<ctype.h>` and `<string.h>` — the two headers where a
wrong answer is silent because the caller is a loop, not a check.

**Was:** `strnlen` declared nowhere and implemented nowhere. That one is a HARD
error at the call site ("call to undeclared function"), so it is the benign
kind — unlike the errno case above, it cannot silently do the wrong thing.

**Now:** in `<string.h>` and `lib/crtl/src/string.c`, stopping at `maxlen` and
returning `maxlen` when no NUL is found, which is the whole reason the function
exists: reading a fixed-width field that may not be terminated.

**Everything else in the batch already agreed with gcc**, including the places
where agreement is not obvious and where drifting would be invisible:

- ctype on `EOF` (all predicates false) and on high-bit bytes — `isalpha(0xE9)`,
  `isspace(0xA0)`, `isalnum(0x80)` — plus the full `isspace` set including `\v`
  and `\f`, `ispunct('_')` and `ispunct('$')`, `iscntrl(0x7F)`, and
  `toupper`/`tolower` passing non-letters and `EOF` through unchanged.
- Comparison SIGN in both directions for `strcmp`/`strncmp`/`memcmp`, and the
  classic trap: `strcmp("\xff", "\x01")` is POSITIVE, because the comparison is
  unsigned.
- `strncpy`'s two-faced contract — it does NOT terminate when it fills the
  buffer, and it DOES zero-pad the whole remainder when it is short.
- `memmove` with overlap in both directions.
- `strchr(s, '\0')` finding the terminator, `strstr(s, "")` returning `s`,
  `strtok` on an empty field, `memchr` searching past an embedded NUL.

**Gated:** all of the above is in `test/crtl_libc_oracle.c` — now 65 lines,
byte-identical to gcc's build of the same file.

## Collected gaps: three printf/scanf bugs (2026-07-31, Track B — CLOSED)

Fourth oracle batch, over `<stdio.h>` — formatting and scanning, which every C
project leans on and where a wrong answer is silent because the caller is
building a string, not checking a result.

### 1. `sscanf("%15s")` abandoned the whole scan — the serious one

`vsscanf` never parsed a field WIDTH. `%15s` therefore reached the
unsupported-conversion `break`, so the call returned a SHORT count and left the
destination untouched:

```
gcc:  scan-n=3 a=17 b=42 s=word
pxx:  scan-n=2 a=17 b=42 s=          <- destination never written
```

`%Ns` is the *safe* spelling every C programmer is told to use instead of bare
`%s`, so this failed precisely on the code that was being careful. A caller who
checks the return sees a mysterious short count; one who does not reads a stale
buffer. Assignment suppression (`%*d`) and a width on any other conversion were
broken the same way, for the same reason.

Now parsed: `*` suppression, a decimal width applied to `%s` (max characters),
`%c` (exact count, no terminator, incomplete field fails), and the numeric
conversions (parsed out of a bounded copy so the width really limits what is
looked at, then `s` advanced by what was actually consumed). `%hd`/`%hhd` now
write `short`/`signed char` rather than `int`, which was a live stack-overwrite
of the adjacent variable.

### 2. `%#o` ignored the `#` flag

`printf("%#o", 8)` gave `10`, gcc gives `010`. Expressed as C99's rule — `#`
raises the precision so the first digit is a zero — rather than as a literal
`"0"` prefix, because the value 0 already satisfies the rule and must stay `0`
rather than becoming `00`. Both cases are pinned.

### 3. `%.0d` of zero printed `0`

C99 7.19.6.1: a precision of 0 with a value of 0 produces NO characters. We
printed `0`. Niche, but it is the kind of thing a column-formatting loop depends
on.

### Everything else in the batch already agreed

Flag/width/precision combinations across `d/u/x/X/o/f/s/c` including `%*d` and
`%.*f`, the length modifiers (`h`, `hh`, `l`, `ll`, `z`), `snprintf`'s return
contract (what WOULD have been written, and truncation without overflow),
`snprintf(NULL, 0, ...)` for sizing, and a file round trip — `fgets`, `ftell`,
`fseek(SEEK_END)`, `ungetc`, `feof`.

**One non-finding worth recording:** the first draft appeared to show a `feof`
divergence. It did not — `printf("...", feof(f), fgetc(f), feof(f))` has
UNSPECIFIED argument evaluation order, so the two builds were legitimately
reading different sequences. Rewritten as statements, both agree. The oracle
test says so at that line, because the next person will be tempted to write it
the short way.

**Gated:** `test/crtl_libc_oracle.c` is now 97 lines, byte-identical to gcc.

## Collected gap: `div`/`ldiv`/`lldiv`/`llabs` absent (2026-07-31, Track B — CLOSED)

Fifth oracle batch, over `<stdlib.h>` and `<time.h>`.

**Was:** `abs` and `labs` only. `div`, `ldiv`, `lldiv` and `llabs` were declared
nowhere, along with the `div_t` / `ldiv_t` / `lldiv_t` structs — all C89 except
`lldiv`/`llabs`, which are C99. The benign kind of missing (a hard "call to
undeclared function"), not the silent kind.

**Now:** declared in `<stdlib.h>` and implemented in `lib/crtl/src/stdlib.c`.
The bodies just compute the pair with `/` and `%`, because those already satisfy
C99 7.20.6.2 on this target — quotient truncates toward zero, remainder takes
the numerator's sign — and re-deriving the rule by hand would be a second place
for it to be wrong. That equivalence is now asserted rather than assumed: the
oracle prints `7/2, -7/2, 7/-2, -7/-2` and the matching `%` row beside the
`div_t` results.

**Everything else in the batch already agreed with gcc**, including the parts
that are easy to get subtly wrong and would be silent:

- Negative-operand division and modulo in all four sign combinations, and
  `lldiv` on a numerator one away from `INT64_MIN`.
- `qsort` with duplicate keys and on a single-element array.
- `calloc` actually zeroing; `realloc` preserving the prefix across a grow.
- `gmtime` on fixed epochs — chosen for where calendar arithmetic breaks: a
  leap day (2000-02-29), a year boundary (2015-12-31 23:59:59), and the epoch
  itself — checking `tm_wday` and `tm_yday`, not just the date.
- `strftime` including `%j` and a literal `%%`.

Fixed epochs and `gmtime` rather than `localtime` on purpose: the test must not
depend on the machine's timezone.

**Gated:** `test/crtl_libc_oracle.c` is now 113 lines, byte-identical to gcc.

## Swept: feature-test macros (2026-07-31, Track B — NOT a library gap)

The last assumption class this ticket names — "feature-test macros & config
that gate which code path a project compiles" — is swept, and it turned out to
be entirely on the COMPILER side, so nothing lands here.

`__STDC__`, `__STDC_VERSION__`, `__linux__` and `__x86_64__` are correct.
Missing: `__unix__`, `__SIZEOF_POINTER__`, `__SIZEOF_LONG__`, `__CHAR_BIT__`,
and `__BYTE_ORDER__` / `__ORDER_LITTLE_ENDIAN__`. The last is the one that
matters — endianness is decided at compile time by hash libraries, compression
and every wire-format parser, and with the macro absent a project silently takes
its fallback branch, which is sometimes slower and sometimes wrong.

Worse, found in the same sweep: **`__LINE__` expands to 0, `__FILE__` to an
empty string, and `__func__` to an empty string** — and when passed as
ARGUMENTS all three arrive as NULL/0. Those three are the entire content of
every `assert` and logging macro in real C, so a corpus that builds and runs
still reports `:0` from an unnamed file, or hands a logger a null pointer.

Filed as [[bug-c-line-file-func-and-predefined-macros-missing]] (Track C).
Deliberately not worked around in `lib/crtl`: a header cannot supply `__LINE__`,
and faking the rest would hide the real gap.

## Sweep status of the classes this ticket lists

| class | state |
| --- | --- |
| header symbols declared-but-unimplemented | swept — census misleading, link-probe instead; `strnlen`, `div`/`ldiv`/`lldiv`/`llabs` were the real gaps |
| `<limits.h>` / `<stdint.h>` / `<inttypes.h>` completeness | swept — correct; inttypes closed earlier |
| errno values + names | swept — **39 of 71 missing**, fixed |
| `<ctype.h>` assumptions | swept — correct |
| struct layouts (stat, off_t width) | swept — `struct stat` diverges but is self-consistent and correct; recorded, not a bug |
| feature-test macros & config | swept — a COMPILER gap, filed for Track C |
| math edge functions | swept — correct |
| stdio / printf / scanf | swept — **3 bugs**, fixed |

All of it is now gated by `test/crtl_libc_oracle.c` against gcc's build of the
same file (113 lines), so the next divergence is caught rather than discovered.

## Swept clean: `<setjmp.h>` and `<fenv.h>` (2026-07-31, Track B — no gap)

Sixth oracle batch. **Nothing was broken** — every case matched gcc first time:
`longjmp` unwinding across frames, the C99 rule that `longjmp(buf, 0)` arrives
as `1`, a volatile local surviving the jump, `fegetround`/`fesetround` round
trips, and `round`/`trunc`/`nearbyint` on the halfway cases.

Gated anyway, as `test/crtl_setjmp_oracle.c`, for a reason the rest of the C
library does not have: **setjmp is codegen-sensitive**. It saves and restores
the frame, so a register-allocation or prologue change can break it while every
other test stays green, and the failure mode is a wild jump rather than a wrong
value. `test/crtl_header_smoke.c` only proved the header COMPILES; nothing
exercised the behaviour, and no Makefile target referenced it.

Kept as a separate file from `crtl_libc_oracle.c` on purpose: `longjmp` unwinds
out of the middle of the enclosing function, so folding it into a large `main()`
with many live locals would make the test about that `main()` rather than about
`longjmp`.

## Batch filed 2026-08-05 — 10 declared-but-unimplemented, all needing PAL work

Found by probing all 361 crtl declarations for an implementation (take the
function's ADDRESS in a program including only its header; an unimplemented one
shows up as a dynamic import). 361 declared, 343 implemented, 18 not — 8 of
those were fixed in [[bug-b-crtl-basic-posix-io-not-implemented]] because the
bridges already existed. These ten remain:

| function | what it needs |
| --- | --- |
| `poll` | `PalPoll` exists; needs a `__pxx_poll` bridge in `pxxcio.pas` |
| `ioctl` | `PalIoctl` exists; same, a bridge |
| `clock_gettime` | no PAL entry; the syscall is already used internally for time |
| `chmod`, `umask` | no PAL entry |
| `msync`, `mremap` | no PAL entry (`sys/mman.h` has the rest) |
| `pread`, `pwrite` | **want a real positional syscall.** A seek/read/seek emulation is silently non-atomic and would differ from every other libc under concurrency — worth doing properly or not at all |
| `atexit` | runtime hook registration, not a syscall; `lib/rtl/atexit.pas` exists |

Reproduce the probe any time: it is a dozen lines of shell over
`lib/crtl/include/**`, and it is how a declared-but-unreachable function is found
before a user finds it. The failure mode is always the same and always quiet —
the program links against glibc, works on the dev box, and cannot run anywhere
else.

## 2026-08-09 (Track B) — corpus pass: zlib clean, tcc surfaces one gap

Worked the ticket's own method: bring up a real project, record the *library*
gaps. Both targets against the PINNED compiler (Track B does not rebuild).

### zlib — PASSING, no crtl gap

Ran the `test-zlib` recipe by hand: gcc oracle from the same 16 TUs, pxx runner
from `test/zlib/runner.c`, outputs diffed. **Byte-identical to the gcc oracle.**
The ticket [[feature-c-corpus-zlib]] still said "2 compiler blockers filed. Not
yet passing" and the Makefile carried a matching "currently blocked" comment —
both stale, both corrected. zlib demands no unmet crtl surface.

### tcc — GAP: `longjmp` is a macro only, so it cannot be used as a value

`library_candidates/tcc/libtcc.c` stops at exactly one thing:

```
error: undeclared identifier passed as argument 4 of '_tcc_setjmp',
       where a pointer is expected — this would call/dereference through NULL
```

Call site (`libtcc.h:106`):

```c
#define tcc_setjmp(s1,jb,f) setjmp(_tcc_setjmp(s1, jb, f, longjmp))
```

It passes **`longjmp` as a function pointer**. `lib/crtl/include/setjmp.h`
provides only function-like macros:

```c
#define longjmp(env, val)   __pxx_longjmp(&(env), val)
```

A function-like macro does not expand when the name is not followed by `(`, so
bare `longjmp` is an undeclared identifier. **C requires this to work**: 7.13
says `setjmp` may be a macro, but `longjmp` shall be an external function.

**FIXED 2026-08-09**, and I nearly did not attempt it. My first write-up called
this a design call needing a choice between three options, because our `jmp_buf`
is a STRUCT rather than the usual array typedef (deliberately — an array typedef
loses its dimension in the C frontend and would be sized as one long), so a real
`void longjmp(jmp_buf, int)` takes the buffer BY VALUE and I assumed that
conflicted with `__pxx_longjmp`'s pointer parameter.

**By-value is fine here**, and that is the whole fix. `longjmp` only ever READS
the saved stack pointer, return address and callee-saved registers, so restoring
from a 128-byte copy restores identical values. Writing through such a copy
would be wrong; nothing does.

So `lib/crtl/src/setjmp.c` defines real `longjmp` / `_longjmp` / `siglongjmp`
forwarding to `__pxx_longjmp(&env, val)`, with the names PARENTHESISED at the
definition so the function-like macro does not expand and eat the declarator,
and `setjmp.h` declares them ahead of the macros. A bare `longjmp` now resolves
to the function; an ordinary `longjmp(env, val)` call still takes the macro and
skips the copy.

**Result:** `libtcc.c` compiles past it — the only remaining diagnostic is
"main function not found", which is correct for a library TU. Regression test
`test/crtl_longjmp_as_value.c` in `make lib-test` checks both spellings (through
a function pointer, and as an ordinary call); `crtl_setjmp_oracle` still passes.

### tcc, second gap: `environ` is undeclared (silently 0)

With the `longjmp` fix in, `tcc.c` builds and runs, but emits:

```
warning: undeclared identifier 'environ' used as value (treated as 0)
```

`char **envp = environ;` therefore becomes NULL rather than the environment
block. POSIX declares `extern char **environ;` in `<unistd.h>`; crtl does not.

This is the "header symbol real code assumes" class this ticket collects, and it
is the WORST shape of it — not a link error but a silent zero, so a program that
walks the environment simply sees none. `feature-c-corpus-tcc`'s own suspect list
asked "environ is referenced — resolved how? verify"; the answer is that it is
not.

**It needs an init-before-main hook, which is the same missing piece `atexit`
needs.** Investigated rather than guessed:

- crtl ALREADY has the environment — `lib/crtl/src/stdlib.c` loads
  `/proc/self/environ` into `pxx_env_buf` for `getenv()`, lazily on first call.
- `lib/rtl/sysutils.pas` has the same thing on the Pascal side, and
  `EnvironmentBlock` already returns an execve-shaped `char **`.
- So the DATA is there. What is missing is that `environ` is a VARIABLE, read
  directly (`char **envp = environ;`) with no call to trigger a lazy load. A
  program that reads it before ever calling `getenv` sees NULL.

Populating it requires running an initializer before `main`, and the C entry
stub is `call main; exit_group(retval)` with no init phase — exactly the gap
[[feature-c-entry-stub-must-run-finalizers]] describes from the other end (it
needs a FINI phase for `atexit`).

**That raises that ticket's value: one entry-stub change unblocks both** the last
declared-but-unimplemented crtl function (`atexit`) and this silent-NULL
`environ`. Worth doing as one piece of work rather than two.

Not faked in the meantime: a lazily-populated `environ` cannot work without the
hook, and a `#define environ (__pxx_environ())` macro would break every
`extern char **environ;` declaration in real code.

### tcc, third gap FIXED: anonymous `mmap`/`mprotect` were no-op stubs

Suspect #1 on [[feature-c-corpus-tcc]]'s list — *"mmap/mprotect are stubs (mmap
returns MAP_FAILED) — tcc_relocate needs real anonymous exec mappings"* — was
real, and is now fixed.

- PAL gained `PalMmapAnonProt(len, prot)` and `PalMprotect(addr, len, prot)`.
  `PalMmapAnon` stays RW-only so its existing callers are untouched;
  `SYS_mprotect` added to all five posix arch tables. The ESP backend refuses
  both, which is the honest answer: no MMU, code runs from flash or IDF-owned
  IRAM, so a fake pointer would be a wrong answer rather than a missing feature.
- crtl's `mmap` now serves ANONYMOUS requests over the PAL and still refuses
  file-backed ones with `MAP_FAILED` — sqlite is the only in-tree caller, its
  mmap I/O is off by default, and it falls back to read/write. `mprotect` and
  `munmap` are real.

Verified with the JIT shape — map RW, write machine code, `mprotect` to R+X,
call it — identical to gcc, and pinned as `test/cmman_jit_exec_pages.c` in
`make lib-test`.

**`tcc -run` works as a result:**

```
$ tcc -run ret7.c     -> exit 7
$ tcc -run say.c      -> exit 3
```

The program genuinely executes. **One narrow gap remains, and it is NOT what I
first guessed.**

I recorded it as "stdout is never flushed … plausibly the same init/fini hook as
atexit and environ". **That is disproven**: crtl's `puts` does not buffer at all
— `lib/crtl/src/stdio.c` calls `__pxx_write(1, s, n)` directly. There is no
buffer to flush, so the finalizer hook has nothing to do with it.

What is actually true, measured:

| under `tcc -run` | result |
| --- | --- |
| `write(1, "x", 1)` | **prints** |
| `puts` / `printf` / `fputs` / `fwrite` | **silent**, every one |
| `puts(...)` return value | **success** — it reports the byte count |
| a genuinely undefined symbol | `tcc: error: unresolved reference to '...'` |
| output redirected to a file | 0 bytes (so not a tty/pipe buffering artefact) |

Ran that next step, and the answer moves this OUT of crtl:

- **The pxx-built host exports no symbol table at all.** `readelf -h` reports
  **0 section headers**, and there is no `.symtab` and no `.dynsym`. `nm` finds
  nothing.
- **tcc's static-build fallback `dlsym` knows exactly four symbols** —
  `tccrun.c`'s `tcc_syms[]` is `printf`, `fprintf`, `fopen`, `fclose` and
  nothing else.

So a `-run` program has essentially nothing to bind libc calls against, which is
a property of how tcc resolves under `CONFIG_TCC_STATIC` plus our minimal ELF —
not a missing crtl function. `write(2)` works because tcc emits it as a direct
syscall rather than a host call.

**This is therefore not a crtl gap and does not belong on this ticket's list.**
The pxx-side fact worth carrying elsewhere is that our binaries emit no symbol
table, so anything that resolves symbols in a running process — a JIT, a
plugin loader, `dlsym` on ourselves — has nothing to work with. Whether that is
worth changing is a Track A/C question about ELF emission, not a library gap.

`tcc -c` and full `tcc -o` linking both work; `-run` is the only affected mode.
Recorded rather than guessed at a second time — the first guess (a missing
stdout flush) was disproven by crtl's `puts` being unbuffered.
