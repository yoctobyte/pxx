---
track: B
prio: 55
type: bug
blocked-by: []
summary: "IOResult returns the raw negative errno (-2 for a missing file, -13 for permission denied) where FPC returns the positive DOS-style code (2, 5). Code written as `if IOResult = 2` silently takes the wrong branch."
status: done
---

# `IOResult` returns a negative errno instead of an FPC code

Found 2026-08-20 by an FPC differential probe over file I/O, alongside
`bug-b-read-of-a-number-from-a-text-file-reads-the-whole-line`.

```pascal
AssignFile(t, 'definitely_missing_file_xyz');
{$I-} Reset(t); {$I+}
writeln(IOResult);
```

| case | FPC | pxx |
| --- | --- | --- |
| missing file | 2 | **-2** |
| permission denied | 5 | **-13** |
| success | 0 | 0 |

pxx passes the negative errno straight through (`SetIO(Integer(n))` in
`lib/rtl/textfile.pas`). FPC reports the DOS-heritage code: 2 = file not
found, 3 = path not found, 5 = access denied, 6 = invalid handle, 100 = disk
read past EOF, 101 = disk full, 103 = file not open, 106 = invalid numeric
input.

It is **compat**, not a crash: the value is nonzero either way, so `if
IOResult <> 0` — how most code spells it — behaves the same. Code that tests
for a specific cause (`if IOResult = 2 then ...`, an entirely normal thing to
write) silently takes the wrong branch, which is why it is a bug ticket and
not a note.

The map belongs next to `SetIO` in `lib/rtl/textfile.pas`: translate the errno
at the point it is recorded, so every caller sees FPC's numbering. Keep the raw
errno out of the public value entirely rather than translating at each call
site — one concept, one place.

Track B (`lib/rtl`).

## RESOLVED 2026-08-28 (frankB) — and it is a **bug**, not compat. The slug is wrong; the frontmatter was already right.

### Classification first, because it was asked

`CLAUDE.md`'s compat table routes this by one question: can a program whose
source is correct Pascal observe a wrong *behaviour*? Yes —

```pascal
{$I-} Reset(t); {$I+}
if IOResult = 2 then ...   { file not found }
```

is ordinary Pascal, and it took the **wrong branch** because we returned `-2`.
That is the silent-wrong-behaviour escape, which the table sends to `bug` in the
owning lane, not to `compat`. The `type: bug` in this ticket's frontmatter was
already correct and the `compat-` in its filename was always misleading — the
ranker reads frontmatter, so nothing was mis-ranked, but a reader skimming slugs
would have deferred it. **Left renamed-in-place rather than actually renamed:
the slug is this ticket's identity and other documents cite it.**

Note it is *not* the deferrable row it superficially resembles. "Our diagnostic
or error number differs" is deferred by that same table — but that row is about
what a program **prints when it dies**. `IOResult` is a value programs **branch
on while running**.

### FPC is not the clean translation this ticket assumed — three corrections

Measured against fpc 3.2.2 by producing each condition and reading `IOResult`
back, rather than working from the DOS-heritage list:

1. **FPC passes unmapped errnos straight through as the positive errno.**
   `ELOOP` comes back as **40**. This is the finding that determined the design:
   had FPC translated everything, an unmapped errno would need a code invented
   for it — and an invented code is a plausible wrong answer with no failure mode
   that reveals it. Because FPC does not, the `else` arm is *FPC's behaviour*
   rather than a fallback of ours.
2. **`path not found` is 2, not 3.** This ticket predicted 3 from the DOS list.
   A missing intermediate directory answers **2** on fpc 3.2.2.
3. **`ENAMETOOLONG` (36) maps to 2**, so the mapped set is a genuine map and not
   an absolute-value in disguise. And `Reset` on a **directory succeeds** (0) on
   both, so that case never reaches the map at all.

The measured table, which is exactly what shipped:

| errno | FPC / now pxx |
| --- | ---: |
| 2 ENOENT, 36 ENAMETOOLONG | 2 |
| 13 EACCES, 20 ENOTDIR, 21 EISDIR | 5 |
| 40 ELOOP | 40 (passthrough) |

**`EPERM` and `EROFS` are deliberately absent.** They could not be produced on
this box without root, so a row for them would be transcription wearing the
appearance of measurement. They take the passthrough arm and may differ from
FPC; that is stated in the source rather than papered over.

### What landed

`lib/rtl/textfile.pas` only. The translation is at **`SetIO`** — the one place a
raw errno becomes a public value, as this ticket specified — so no caller knows
and no call site can forget. Non-negative values pass through as already-final
codes.

**One thing this ticket did not anticipate: the `SetIO(-1)` sentinel was
ambiguous as well as negative.** Five sites used `-1` to mean "bad state", but
`-1` negated is `EPERM`, a real errno — so a genuine `EPERM` and our sentinel
were indistinguishable. They now use FPC's own codes for those states directly:
**103** (file not open) for the two `Handle < 0` guards, **102** (file not
assigned) for `Erase` with no name and both `Rename` refusals — 102 being
measured as FPC's answer for renaming an open handle.

### Test, negative control, gate

`test/lib_ioresult_fpc_codes.pas`, wired into `make lib-test`, sentinel
`IORESULTCODES OK`. It builds its own fixtures (`PalMkdir`, `PalSymlink`,
`PalChmod`), covers all ten measured rows plus the 102/103 states, and asserts
the underlying invariant as itself: **no failure surfaces a negative code, on
either arm of the map.** The EACCES row is guarded for a user who can read a
mode-000 file, and that skip **prints** — an invisible skip is how a suite passes
without testing anything.

**Negative control:** restoring `SetIO`'s passthrough fails the test with 9
errors, including both invariant rows.

`make lib-test` REAL EXIT=0, redirected not piped. Synapse jobs skipped
(tree held aside under the Track A bug), standing caveat.

## Log
- 2026-08-28 — resolved, commit 89fec8bdf.
