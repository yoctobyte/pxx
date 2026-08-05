# Handoff — Track B bug hunt, night of 2026-08-04/05

**This is a self-prompt for a fresh context, not a spec.** It is a record of
where I stopped and what I learned; `CLAUDE.md` remains the authority on gating.

Tree state at handoff: `475b498a0`, clean, everything pushed, `gate.sh lib`
GREEN, self-host fixedpoint converges.

---

## The prompt

> Track B (libraries), continuing an overnight bug hunt. Everything is pushed
> and green at `475b498a0`; nothing is half-landed.
>
> **Do not spend time on float formatting or libm rounding.** The user has said
> so twice and was right both times — it is this repo's rabbit hole. Wrong
> *values* and crashes are in scope; ULP-chasing against a high-precision oracle
> is not.
>
> The productive loop last session was **not** working the ticket queue (Track
> B's `bug-` queue is empty) — it was *finding* bugs with three tools, all of
> which still have road left:
>
> - `tools/fpc_diff_probe.sh` — 168 cases, FPC as oracle, currently 0 new
>   divergences. Untouched surface: generics, interfaces, operator overloading,
>   `TStringList.Sorted`, date arithmetic beyond the basics.
> - `tools/lib_cross_sweep.sh` — builds every `test/lib_*.pas` for
>   i386/arm32/aarch64 and diffs against the x86-64 run. Found four of the six
>   urgent bugs below. riscv32 is opt-in (`SWEEP_RISCV32=1`) and should stay
>   that way — it is a stage-1 port with no allocator, so ~45 rows fail by
>   construction and bury real findings.
> - `tools/crtl_decl_probe.sh` — takes each crtl declaration's address and
>   checks whether it becomes a dynamic import. 361 declared, 353 implemented.
>   The 8 that remain need PAL bridges (see
>   `feature-crtl-implement-libc-assumptions`).
>
> A fourth angle worth building: nothing yet does for **C behaviour** what
> `fpc_diff_probe` does for Pascal — a gcc-oracle differential over crtl's
> *existing* functions rather than its missing ones.

---

## What landed (11 bugs, Track B)

Pascal RTL: `Format` followed printf's grammar instead of Delphi's (4 defects);
four integer parsers that disagreed with each other, incl. `'-9223372036854775809'`
returning the *maximum positive* value; `IntToStr(Low(Int64))` returning `-`;
`Pos('')` returning 1; `TStrings.Text` hardcoding CRLF; `ChangeFileExt('.hidden')`
destroying the filename; `O_DIRECTORY` using the x86 value on ARM (directory
listing was dead there).

crtl: the socket veneer was never pulled by any header; `<wchar.h>`/`<wctype.h>`
were declarations only; `read`/`write`/`close`/`lseek` unreachable from
`<unistd.h>`; `printf("%a")` segfaulted every 32-bit target.

Plus a compiler warning on the user's instruction: a duplicate definition in the
same scope is no longer silent (Pascal side only — see below).

---

## Open, mine, ranked by what I would pick up first

**Urgent, filed for other lanes — do not fix under B, but they are the best
leads if the user reassigns:**

| ticket | one line |
| --- | --- |
| `bug-a-virtual-method-int64-in-and-out-32bit` | virtual method taking *and* returning Int64 miscompiles on every 32-bit target; live in `TStream.Position`; riscv32 is ESP32 |
| `bug-a-static-array-of-managed-whole-assign-loses-data` | `b := a` on a static array of strings copies nothing |
| `bug-c-int64-to-double-cast-truncates-on-32bit` | `(double)9007199254740991` is `-1` on i386/arm32; Pascal is correct on the same targets |
| `bug-a-arm32-write-after-free-kills-four-lib-tests` | `-dPXX_HEAP_DEBUG` says WRITE AFTER FREE; bignum alone and generic alloc churn do *not* reproduce |
| `bug-a-i386-int64-arg-high-half-uninitialized` | `IntToStr(Abs(n))` silently wrong; the garbage *moves*, so passing cases prove nothing |
| `bug-p-string-char-relational-compares-lengths` | `<`/`>` between a string and a Char compare lengths; `=` is fine, which is why it hides |
| `bug-p-program-function-does-not-shadow-used-unit` | a program's own function loses to a used unit's; FPC prefers the program's. Same missing rule makes pxx pick the *first* of two units where FPC picks the last |

**Where the last thread stopped:** `bug-c-string-h-compiles-stdlib-c-twice`.
`#include <string.h>`, nothing used, compiles `lib/crtl/src/stdlib.c` twice.
Root-caused: `CPreprocess` (`cpreproc.inc:2605`) clears the macro table per
*invocation* — right for Pascal's unit-local `{$DEFINE}`, wrong for C's
TU-global `#define` — and `cparser.inc:8134` calls it a second time for the
synthetic late pull, so no include guard can be visible there. **An include
guard does not fix it; that was measured, not assumed.** The dedup marker
(`CrtlSrcPulled[]`) is a never-reset global that *both* pull sites consult, so
the remaining suspect is its exact-string path comparison: the two pulls build
the path by different routes. Print both strings at the two sites first. The
C-side duplicate-definition warning is written and verified and lands the moment
this is fixed — the exact diff is in that ticket.

---

## Hard-won, would repeat

- **Track B gate is `tools/gate.sh lib`, run UNPIPED.** Piping masks the exit
  code, and `; echo "EXIT=$?"` makes the *echo's* status the task's — read the
  log body, always.
- **Any `lib/crtl` or `lib/rtl` change owes a cross run.** `lib-test` is x86-64
  only and Track T's matrix excludes the lib tests, so *nothing in the tree*
  runs `lib/rtl` on a 32-bit target. That gap is where four urgent bugs were
  hiding. For crtl also re-run `tools/run_c_conformance.sh ... --target i386`.
- **Assert the LINKAGE, not just the output.** A missing crtl function still
  produces correct output on a glibc host — only the `DT_NEEDED` shows it.
  `lib-test` now checks this for four tests; keep doing it.
- **`git stash push <clean paths>` creates NO entry**, so the next `pop` takes a
  sibling agent's stash. Name them (`-m`) and pop by ref. This bit once.
- **When the oracle looks wrong, suspect the harness.** Cost me three detours:
  `%a` unsupported made a libm probe print `%a`; Python's `float.hex()` pads
  where C's `%a` does not; and *twice* I read `errno` in the same argument list
  as the call that sets it (unspecified order — gcc and arm disagree, both
  legally).
- **A no-oracle skip is not a pass.** `fpc_diff_probe.sh` used to return
  silently when FPC could not compile a case; two of my own cases were disarmed
  by a missing `uses` and looked like coverage. It now counts and prints skips.
- **The local self-host seed goes stale.** `compiler/pascal26` was six days old
  and could not compile current source. `cp stable_linux_amd64/default/pinned
  compiler/pascal26` reseeds it. A/B before blaming anyone.
