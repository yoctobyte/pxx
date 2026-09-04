# C: two conflicting typedefs for one name are accepted silently, last wins

- **Type:** bug (Track C — C frontend, the typedef registration in
  `compiler/cparser.inc`)
- **prio:** 50
- **Status:** done
## Repro
```c
typedef long long T;
typedef long T;
int main(void){ return (int)sizeof(T); }
```
`gcc -m32`: `error: conflicting types for 'T'; have 'long int'`.
`pxx --target=i386`: compiles, no diagnostic, exit code 4 — the LAST typedef
won.

C11 6.7 permits a repeated typedef only when it names the *same* type. These
do not, so this must be an error.

## What it cost
It hid a genuine crtl inconsistency for the whole life of the file.
`<time.h>` had `typedef long long time_t` (with a comment promising 64-bit on
every target so Y2038 never appears) while `<sys/types.h>` had
`typedef __time_t time_t` with `__time_t == long`. Including `<time.h>`
auto-pulls `crtl/src/time.c` (`CPAutoPullCrtlImpl`), which reaches
`<sys/types.h>`, so the `long` definition arrived last and won — and no
diagnostic said the header's promise had been overridden.

The damage is not the width, it is that the width became a function of what
else the translation unit pulled in. Measured with the conflict restored, one
TU giving two answers for one type on i386:

```
sizeof(time_t)=4   sizeof(long)=4     <- the sizeof rows AGREE
static time_t g;   laid out at 8      <- and the global disagrees with them
```

On x86-64 the whole thing is invisible, because `long` and `long long` are the
same width there. The shape that passes where you test.

The crtl half is fixed (`<time.h>` now uses `__time_t`, one definition) and
`test/c_time_t_one_definition.c` guards it on i386/arm32/riscv32. The frontend
half — refusing the conflict — is this ticket.

## Care needed
Not a free error to add. `lib/crtl` deliberately redefines names the Pascal RTL
also spells, and `cparser.inc`'s cross-namespace binding has three rungs of
measured special-casing around exactly that. The check wanted here is narrow:
two `typedef`s in C for one name whose target types differ. Run the corpora
(zlib, lua, quickjs, the 220-case conformance suite, busybox) before landing —
a second conflicting pair somewhere would currently be compiling quietly.

## Resolution

Refused, in `AddCTypedefEx` (`compiler/cparser.inc`), which is the single point
where an existing typedef row was overwritten.

**The rank is what makes it work on 64-bit.** `TTypeKind` collapses `long` and
`long long` onto `tyInt64` wherever a pointer is eight bytes, so a check
comparing only the resolved kind refuses this ticket's own reproducer on i386
and ACCEPTS it natively — passing exactly where everyone tests, which is the
failure mode this ticket is about. The typedef row therefore carries a long
RANK beside the kind, the same distinction `SymCLongRank` already keeps for
`_Generic`. Refused on x86-64, i386, riscv32, aarch64 and arm32.

**Armed only for a source `typedef` statement**, via a flag the registration
consumes and clears. `lib/crtl` deliberately redefines names the Pascal RTL also
spells and cparser's cross-namespace binding has three rungs of measured
special-casing around exactly that, so an unconditional check would be a much
wider claim than the defect justifies. The aggregate arms are ALSO left
unarmed: `typedef struct {...} S;` reached twice mints a fresh anonymous record
each time, so record ids differ by construction and arming it would reject
unguarded double inclusion. That case should be measured before it is armed.

**The first draft refused code gcc accepts**, and its own test caught it on the
first run. `typedef T Alias;` after `typedef long T;` is legal — both name the
same type — but the rank was read from the `long` TOKENS spelled at that
occurrence, and an alias spells none, so rank 0 met rank 1. Fixed by making the
rank survive resolution through a typedef name.

**That also fixed `_Generic`, and not the row I expected.** It reads the same
two flags. Ablation (stash, rebuild, measure, restore) shows the broken row was
`typedef long long TLL;` selecting the `long:` arm — with no rank recorded the
two arms are indistinguishable by kind natively and `long:` matches first. The
ALIAS row was accidentally right by that same collapse. Three of the five rows
in `test/c_generic_selects_through_a_typedef_alias.c` pass on a compiler that
records no rank at all, so any one of them alone would be a row that cannot
fail.

**Corpora, as this ticket required before landing** — every one with the check
armed and ZERO false refusals:

| corpus | result |
| --- | --- |
| c-testsuite conformance | 220 pass, 0 fail, 0 skip (run twice, once per binary) |
| `tools/c_corpus_probe.sh` | 3 programs, 3 identical, 0 skipped, 0 failed |
| lua core (`test/lua/runner.c`) | compiles; 6 of 6 lua programs match expected |
| sqlite amalgamation (9MB, one TU) | compiles and runs correctly |
| busybox, 394 applets, i386, `--separate` | 521 objects, **938/938 byte-identical** to the `gcc -m32` oracle |

The busybox sweep snapshotted binary `2000b8f612d4`, which is the build BEFORE
the rank inheritance, and that is still a valid instrument for the final
`dad98c7a5537` — stated because a snapshot that lags is normally exactly the
kind of thing that lies. Two reasons, both checked rather than assumed: the
refusal delta only ever REJECTS, so the sweep ran the stricter of the two
compilers; and the rank delta cannot reach a byte busybox emits, because every
consumer of `CTypeLong`/`CTypeLongLong` terminates in `_Generic`
(`CExprLongRank` -> `CExprCG` -> the controlling expression, cparser.inc:1776)
and busybox contains zero uses of `_Generic`.

**The crtl half was already closed** and its guard (`c_time_t_one_definition.c`)
stays; that row's Makefile comment still described the frontend defect as live
and is corrected in the same commit.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
