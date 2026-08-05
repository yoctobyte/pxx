# Handoff — Track B bug hunt, night of 2026-08-05 (second night)

**A self-prompt for a fresh context, not a spec.** `CLAUDE.md` remains the
authority on gating. Predecessor: `2026-08-05-track-b-bughunt.md`.

Tree state at handoff: clean, everything pushed, `gate.sh quick` + `gate.sh lib`
GREEN, self-host fixedpoint converges.

---

## The prompt

> Track B (libraries), continuing the bug hunt. Everything is pushed and green;
> nothing is half-landed.
>
> **Do not spend time on float formatting or libm rounding.** The user has said
> so three times now. Wrong *values* and crashes are in scope; ULP-chasing is not.
>
> The loop that works is not the ticket queue — it is *finding* bugs with the
> differential probes. There are now four:
>
> - `tools/gcc_diff_probe.sh` — **new this session.** 98 cases, gcc oracle,
>   libc-free pxx side, `--target i386|arm32|aarch64` cross mode. Found 8 bugs
>   in three batches. Clean on all four targets.
> - `tools/fpc_diff_probe.sh` — 215 cases (was 168). Generics, interfaces,
>   operator overloading and core class/exception semantics are all now covered
>   and all match FPC. Untouched: `Currency`, `WideString`/`UnicodeString`,
>   class helpers, `array of const`/`TVarRec`, threads.
> - `tools/lib_cross_sweep.sh` — unchanged; the arm32/i386 reds in it are the
>   known pre-existing families, not regressions (A/B them before believing one).
> - `tools/crtl_decl_probe.sh` — 366 declared, **359** implemented (was 353).
>   The last 7 are filed as one ticket.

---

## What landed (17 bugs, Track B unless noted)

**The C double-compile** (`bug-c-string-h-compiles-stdlib-c-twice`, the previous
handoff's open thread): *neither lead in the ticket was right.* `stdlib.c` was
auto-pulled exactly once — `CLexAppend` strips the user EOF, so `ParseCProgram`'s
main pass 2 walked into the appended crtl region and the dedicated crtl pass 2
compiled it again. 159754 B/51 warnings → 132374 B/0.

That let the C duplicate-definition warning land, which found three real crtl
duplicates: `stdlib.c`'s seed-only `time()` stub expanding via `time.h`'s macro
into a second `__crtl_time` that always returned 0; `gettimeofday` at two
different precisions; `netinet/in.c` hijacking `close` for every file in the TU.

**crtl behaviour** (all from `gcc_diff_probe`): `isprint('\t')` true; `fread`
issuing one `read()` and never setting EOF; `strftime` returning the truncated
length instead of 0; `strtol` eating the `x` of a bare `"0x"`; eleven syscall
veneers returning the kernel's raw negative errno so `perror()` printed
"Success"; `sscanf` missing `%[...]` and `%n`; `asctime`/`ctime`/`timegm`
missing entirely; `clock_gettime` silently binding to libc.so.6.

**Cross-target:** `__pxx_exit` hardcoded `exit_group` to **231**, x86-64's
number — on i386/arm32 that is `fgetxattr`. `exit(3)` measured **0** on i386,
arm32 and aarch64. Every cross-target program reporting failure through `exit()`
reported success. (`return 3` from `main` was unaffected, which is why nothing
caught it.)

**RTL:** `TStringList` gained `Sorted`/`Duplicates`/`CaseSensitive`/`Find`, and
`Sort` was **case-sensitive** where FPC's is not.

**Tooling:** `tools/run_target.sh`'s i386 path sent the program's stderr to
`/dev/null` — every i386 run silently lost its diagnostics, including for
`run_c_conformance.sh`, which compares combined stdout+stderr.

## Filed, not fixed — the best leads if the user reassigns

| ticket | one line |
| --- | --- |
| `bug-a-explicit-int64-cast-of-nativeint-does-not-extend-on-32bit` | **the sharpest.** `Int64(n)` for a `NativeInt` reinterprets 8 bytes on 32-bit; `Int64(5)` is `4294967301`. Implicit widening is correct, `Int64(@x)` is correct |
| `bug-a-pointer-difference-as-vararg-pushes-8-bytes-on-32bit` | `printf("%d %d", p-q, 7)` prints `3 0`; shifts every later argument |
| `bug-a-bool-conversion-does-not-normalise-to-0-or-1` | `_Bool b = 256` is FALSE; `_Bool b = ptr` is the pointer's low byte |
| `bug-c-header-with-a-body-compiles-twice-across-the-macro-reset` | stdarg.h's static helpers, root-caused to a third `CPreprocess` invocation |
| `feature-b-crtl-last-seven-unimplemented-declarations` | `atexit` needs the C entry stub to call `__pxx_run_finalizers`; `chmod`/`umask` are cheap |
| `compat-pascal-inline-generic-specialization`, `compat-pascal-supports-three-arg-out-form` | FPC syntax pxx rejects |
| `bug-b-crtl-esp-close-cannot-dispatch-socket-vs-file` | ESP-IDF only; POSIX is fine |

---

## Hard-won, would repeat

- **The probe accused the compiler 8 times and was wrong 6 of them.** Every one
  was the harness. The tells, in order of how much time each cost:
  1. **Reading a side effect in the argument list of the call that causes it** —
     `printf("%d [%s]", fread(b,…), b)`, `printf("%d %d", ftell(f), fgetc(f))`,
     `printf("%d %d", strtol(s,&e,0), e-s)`, `printf("%d %d %d", ctr(), ctr(), ctr())`.
     Argument order is unspecified, gcc goes right-to-left, and **pxx orders
     arguments differently on arm32/aarch64 than on x86-64** — all legal. Four
     separate detours. The rule is now in the tool header.
  2. **`-std=c99 -w` on the oracle.** Strict c99 hides the POSIX declarations
     (`strsep`, `strtok_r`, `timegm`), so gcc took them as implicit `int`,
     **truncated the returned pointer to 32 bits, and segfaulted**. `-w` hid the
     warning. Now `-std=gnu99` plus `-Werror=implicit-function-declaration`,
     which survives the `-w` and turns that shape into a counted SKIP.
  3. **Fixed `/tmp` paths in filesystem cases.** Two runs shared files, and a
     leftover was *masking* the `clock()` divergence — arm32 flickered between 0
     and 1 findings. Cases now write under the per-run scratch dir.
- **When the ORACLE looks wrong, it is the harness.** gcc segfaulting or printing
  garbage is never a pxx bug. Every time I checked that first, it was quick.
- **A green cross run is not a clean one.** `lib_cross_sweep` has many
  pre-existing reds. A/B against `git show HEAD:<file>` before claiming or
  denying a regression — I did this for `lib_classes` and it was byte-identical.
- **`grep -v '\[known\]'` lies about the count.** Twice I filtered the DIFF lines
  and concluded "0 new" while the summary said otherwise. Read the summary line.
- **Editing a probe file with a Python slice between two markers deleted
  content.** The tell was the run reporting 1 known where it had reported 13.
  `git checkout` and redo; append at the summary anchor, never slice.
- **A 32-bit bug's garbage MOVES with stack layout.** An earlier repro had the
  record-field case failing and the local passing; adding one `writeln` swapped
  them. A passing site proves nothing about its neighbour.
- **"It works" and "it links libc-free" are different questions.** `clock_gettime`
  produced correct values for months while pulling in `libc.so.6`. `readelf -d`
  is the check; `crtl_decl_probe.sh` automates it.
