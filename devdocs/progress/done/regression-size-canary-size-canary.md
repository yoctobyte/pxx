---
prio: 60
track: A
status: done
---

> **Track T by default: no lane could be inferred** from `tools/size_canary.py`. This is a FALLBACK, not a finding — nothing here says the defect is Track T's, only that the test source did not name an owner. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# advisory: size-canary#src:tools/size_canary.py red at 83fb0ef72419 (auto-filed by twatch)

- **Type:** advisory (NOT a gate — nothing day-to-day depends on this path; a notice for the owning track) (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T13:24:51Z
- **Test source:** tools/size_canary.py

## Repro
`tools/testmgr.py --tier native --job 'size-canary#src:tools/size_canary.py'` at 83fb0ef72419b46cf22dd1ce57885950574d69ef

## Range
> **The named sha `83fb0ef72419` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `83fb0ef72419`, last good `42fde2a7e025`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
size-canary: baseline 4039216a7f25 (2026-08-30T00:58:40+02:00)
  subject              code    d(code)         data    d(data)          bss     d(bss)
  esp32c3-bare        66252     +15724        496       +152     103692          0
  esp32s3-bare        56684     +13232        496       +152     103692          0
  esp32s2-bare        56684     +13232        496       +152     103692          0
  esp32-bare          56684     +13232        496       +152     103692          0
  x86_64-empty        69400      +8121       2712       +752      42452          0

size-canary: 5 FAILURE(S)
  esp32c3-bare.code: 50528 -> 66252 (+15724, +31.1%), over the allowed 55580
  esp32s3-bare.code: 43452 -> 56684 (+13232, +30.5%), over the allowed 47797
  esp32s2-bare.code: 43452 -> 56684 (+13232, +30.5%), over the allowed 47797
  esp32-bare.code: 43452 -> 56684 (+13232, +30.5%), over the allowed 47797
  x86_64-empty.code: 61279 -> 69400 (+8121, +13.3%), over the allowed 67406

A size that moved is not automatically a defect — but it is always a decision. Either fix what grew, or re-baseline with tools/size_canary.py --update and say why in the commit.

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## Re-laned T -> A, prio 40 -> 60, and a named cause (coordinator, 2026-08-30)

The Track T header above says so itself: *"a FALLBACK, not a finding — nothing
here says the defect is Track T's."* It is Track A's, and the fallback lane is
exactly why an advisory this large sat untriaged. **This is now in the pinned
binary**: v396 (`26cbbf4169fd`, 14:38Z) is downstream of the cause, so every
Track B/D/E build made since carries the growth.

### It is not an ESP regression — every subject grew, including an EMPTY program

```
esp32c3-bare   50528 -> 66252  +15724  +31.1%
esp32s3-bare   43452 -> 56684  +13232  +30.5%
esp32s2-bare   43452 -> 56684  +13232  +30.5%
esp32-bare     43452 -> 56684  +13232  +30.5%
x86_64-empty   61279 -> 69400   +8121  +13.3%
```

**`x86_64-empty` is the diagnostic row.** A codegen regression cannot grow a
program with no code in it. Uniform growth across five unrelated targets, one of
which is empty, says something was added to the *baseline every binary links*,
not to anything the compiler emits for user code.

### Hypothesis, with the falsifier that settles it

Four commits in the range `42fde2a7e025..83fb0ef72419`; only one touches a file
that lands in every binary:

| commit | file | why it can / cannot explain this |
| --- | --- | --- |
| **`bfe82dd79`** UTF-16 runtime half | `compiler/builtin/builtinheap.pas` **+278** | a builtin runtime unit — **the only candidate** that grows an empty program |
| `d61f404f3` `tyWideString` kind | `compiler/defs.inc` +49 | additive type-table entry, emits nothing |
| `c5b8442e1` cdecl slice 2 | `compiler/ir.inc` +40 | prologue shape for `cdecl` procs; an empty program has none |
| `83fb0ef72` | tstate only | touches no buildable file |

`bparser.inc:714-830` documents that `builtinheap` is pulled in wholesale through
one door — `USES <unit>` during the parse — and that shims are emitted only when
builtinheap is loaded. So the granularity is **the unit, not the procedure**:
once anything pulls builtinheap, all 278 new lines of wide alloc, concat and both
transcoders come with it, whether or not the program mentions a widestring. That
is the same missing mechanism as
[[bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce]], and this is the
first time it has cost 30% of an ESP image.

**This is inference from the file set, not a bisect.** The falsifier is one
command and it is cheap — `tools/size_canary.py` at `bfe82dd79` and at its
parent. If the step is not there, the reasoning above is wrong and the empty-row
argument needs a different culprit.

### It is a decision, and the canary says so

> *A size that moved is not automatically a defect — but it is always a decision.
> Either fix what grew, or re-baseline with `tools/size_canary.py --update` and
> say why in the commit.*

Three ways out, and they are not equivalent:

1. **Emission-level DCE** — the root-cause fix, closes the hello-world ticket too,
   and the only one that stops the *next* runtime addition repeating this.
2. **Make the wide runtime lazily referenced** — narrower, keeps the UTF-16 work
   out of programs that never name a widestring. Cheaper than (1) and does not
   generalise.
3. **Re-baseline** — legitimate only if the growth is judged permanent and
   acceptable. **Not acceptable unreviewed on ESP**: +13KB on a 43KB bare image
   is a third of the flash budget on a target whose whole campaign is size, and
   that is an owner-visible trade, not a canary `--update`.

Do NOT re-baseline to clear the red before someone with the ESP budget in view
has looked at it. A canary silenced by moving its line is a canary deleted.

## Partly fixed at `1a526a89d` — and the job is STILL RED (coordinator, 2026-08-30)

frankwasm confirmed the cause by measurement (two isolated worktrees at
`bfe82dd79` and its parent `0a7d649c6`, each seeded with the sources touched
afterwards so `make` could not no-op — both printed `converged after 1 round(s)`),
then landed a `{$ifndef PXX_ESP}` guard on the four wide functions.

**The acute part is gone. One row remains over the line.**

| subject | before guard | after guard | allowed | verdict |
| --- | ---: | ---: | ---: | --- |
| esp32c3-bare | 66252 | **50532** | 55580 | restored to parent's exact number |
| esp32s3-bare | 56684 | **43452** | 47797 | restored to parent's exact number |
| esp32s2-bare | 56684 | **43452** | 47797 | restored to parent's exact number |
| esp32-bare | 56684 | **43452** | 47797 | restored to parent's exact number |
| **x86_64-empty** | 69400 | **69400** | 67406 | **STILL OVER by 1994 bytes** |

**Read the number, not the verdict.** This job stays RED until step 7a of
[[feature-unicodestring-model]] moves the wide runtime into a separately-pulled
`builtinwide` unit. While it is red, a *new* x86_64 size regression cannot change
the job's verdict — it can only change the number. **69,400 is the figure to
compare against; anything above it is a second, unrelated regression hiding under
this one.** That is the cost of leaving it red and it is why 7a is not optional.

Exact restoration on all four ESP rows — not approximate — is what says the
growth had a single cause and all of it was removed.

**Two things checked rather than assumed, both of which changed the commit:**

- The coordinator required the guard to move declarations, bodies **and** callers
  together, since guarding only the first two is exactly
  [[bug-a-builtin-pas-calls-a-declaration-that-esp-compiles-out]]. frankwasm
  grepped all four symbols across every `.pas`/`.inc`/`.py`/`.sh`: declarations,
  bodies and one test, nothing else. **No third arm exists**, so the double case
  cannot arise here.
- `test_widestring_transcode.pas` needed **no** ESP skip. It already fails to
  build on hosted xtensa (a sysutils function-result limit) and bare esp32
  (`platform_backend` not found) **on `pinned`, at the same two sites, before the
  change**. Adding a skip would have recorded a restriction that was neither new
  nor this commit's.

`var s: widestring` compiles and runs on bare esp32 today (43,516 bytes) because
`widestring` is still an alias for a byte string — so the guard introduces no
confusing diagnostic. What a bare-ESP program *should* do when it names a real
UTF-16 type becomes live at 7b, which is when 7a has removed the reason to care.

## GREEN at `c59bcb7f0` — resolved (coordinator, 2026-08-30)

```
size-canary: 5 subject(s) within their allowances
x86_64-empty  65304  (+4025)    <- the parent's EXACT number
```

Step 7a moved the wide runtime into a separately-pulled `builtinwide` unit behind
a token-scan predicate, on `wasibackend.pas`'s shipped shape. **All five subjects
within allowance; the 69,400 recorded above as "the figure to compare against" is
retired.** 65,304 is precisely what the parent measured in the worktree A/B that
confirmed the regression — the same exactness test the ESP guard passed, applied
to the row the guard could not fix.

**The `{$ifndef PXX_ESP}` guard is GONE, not kept beside the unit split.** An
`{$ifndef}` cannot express "this program does not use UTF-16" — which is exactly
why it fixed the four ESP rows and left x86_64 paying 4 KB. Keeping both would
have left a target-shaped special case sitting under a program-shaped fix, which
is the second-path smell `normalise-dont-special-case` names.

**The number that makes the fix legible:** `var s: widestring` now compiles to
**69,400 B — exactly what the EMPTY program cost before this commit.** The cost
did not shrink; it moved onto the programs that ask for it. That is the entire
claim in one number, and it is measured rather than argued.

Four behaviours measured, not three: empty program back to baseline; naming the
type pulls the unit and runs; bare esp32 naming it still builds at 43,516 B
*without* pulling it; native string corpus unchanged.

Two traps the template forced, both avoided: `PXXHdrSetMeta` is
implementation-only in builtinheap so the two calls write `PXX_HDR_META`
directly, and the pointer aliases are **re-declared locally rather than
exported** — exporting `PWord` would silently re-type a user's own. Duplicating
a type alias is not a second code path; getting `PWord` wrong is.

Resolves at `c59bcb7f0`.
- 2026-08-30 — resolved, commit PENDING-COMMIT.
