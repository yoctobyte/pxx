---
track: T
prio: 25
type: feature
status: done
found: 2026-08-30
found-by: claude-T
---

# An external alignment oracle: what is left after `df98fea47`, measured

**Filed at 35, raised to 55, now 25 — and the scope is a tenth of what it was.**
The re-price is not a change of mind; it is the result of running the exclusion
before building, which is what the ticket itself told the implementer to do.

## What I set out to build, and why it does not exist as specified

The original proposal was `sh_addr % sh_addralign == 0` over the section header
table of every emitted binary. Four measurements at `46316ba8b`, binary
`1ff8acbe123b`:

1. **PXX executables have no section header table at all.** `readelf -S` says
   *"There are no sections in this file"* — one `PT_LOAD` covering everything,
   and the code/data boundary is internal to it and described nowhere. The
   `.map` file beside the binary is a symbol map: it carries `Base Address` and
   `Code Offset`, not the data base. **The subject of the invariant is not
   observable in the default artifact.**
2. **With `-g` it is.** The debug path writes a real table — `.text`, `.data`,
   `.bss`, with correct addresses and `sh_addralign = 8`. So the check is
   implementable, but only on a `-g` build.
3. **And there it is vacuous.** On all four Linux targets `.data` lands
   page-aligned — `0x414000`, `0x0805F000`, `0x424000`, `0x0807D000` — because
   `PadCodeToPageBoundary` runs unconditionally for executables. Page-aligned
   implies 8-aligned, so the check passes whether or not the fix is present.
4. **The compiler already asserts it, and better than an external oracle could.**
   `AlignCodeForData` establishes the invariant at 3 sites and
   `CheckDataBaseAligned` verifies it at 3 sites — one immediately after each of
   the three `dataBase :=` computations. Coverage is exact, and it is checked
   **where the value is used, not where it is established**, which is precisely
   the case an external oracle was wanted for (*"a writer that computes dataBase
   without calling AlignCodeForData"* — its own comment).

### The `-O0` clause was directionally right and named the wrong concealer

The original ticket said to check with padding-producing passes off, because
the concealer was *"an optimisation's padding"*. Measurement says the concealer
is `PadCodeToPageBoundary`, which is **not** an optimisation and is
**unconditional** for Linux executables. So `-O0` does not remove it, and a
`-O0` check would have been just as vacuous. The principle survives — check
where the concealer is absent — but the concealer had to be identified, not
assumed. It is a page pad, not a `-O` pass.

## What is actually left

One thing, and it is narrow: **ESP bare-metal images**, where the page pad is
skipped outright (`elfwriter.inc`'s own note lists this among the four routes
that take the pad away, and says such images *"have been misaligned all
along"*). That is also the one target family whose hardware faults rather than
absorbing it.

So the residual check is:

- for an ESP bare image, assert the data base ≡ 0 (mod 8) — compared against
  **`ELF_DATA_ALIGN`, not against the file's own `sh_addralign`**, because a
  value checked against its own claim is checked against nothing;
- run it where the pad is absent (`--platform=esp --esp-profile=bare`), which
  is the only configuration where it can go red;
- and **make it fail once before trusting it**: revert `AlignCodeForData` in a
  throwaway worktree and confirm the check declines. A check that has never
  declined is a check nobody has evidence about.

The remaining argument for an external check, and it is real but small: the
in-compiler assert is three lines in a self-hosting compiler, compiled by
itself. A codegen bug that broke the assert would break it silently. An external
reader is immune to that. That is worth 25, not 55.

## What it is NOT worth doing

- **Do not** build the general `sh_addr % sh_addralign` sweep. It is vacuous on
  every artifact PXX currently emits, for the reasons measured above.
- **Do not** answer it by running everything under xtensa. That makes the one
  faulting target the oracle for a property all targets share. (This anti-goal
  survives the re-scope intact; it was the ticket's best line.)

## Found on the way

[[bug-a-emit-obj-on-x86-64-produces-an-object-with-no-symbols-data-or-relocations]]
— looking for objects with real sections turned up that `--emit-obj` on x86-64
emits `.text` and nothing else: no `.data`, no `.bss`, zero relocations, and
four symbols of which none is defined. Filed to Track A.

Gate: `tools/pasmith_*_devtest.py` green; the negative control above is
mandatory, not optional.

## Log
- 2026-08-30 — re-scoped 55 -> 25 after measuring; NOT resolved. A stale
  resolve line stood here, residue from a `progress.sh resolve` run by mistake
  while moving the file. Removed rather than filled: no work landed, so there is
  no sha to fill it with.
