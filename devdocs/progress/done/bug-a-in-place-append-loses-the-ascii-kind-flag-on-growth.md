---
track: A
prio: 75
type: bug
summary: "`9ffbba0bd perf(A): append in place for s := s + x` loses the managed block's ascii kind flag when the string grows through the new inline resize path, so an all-ASCII string built by accumulation reports IsAscii=false. Master is RED on test_managed_block_meta. The test anticipated exactly this — its own comment says the resize path 'must not lose or invent the flag'."
status: done
owner: agent-an
---

# In-place append drops the ascii kind flag when the string grows

- **Type:** bug (regression, master is RED) — **Track A**.
  Found by the Track T watcher at `cdff889a0bfe` (native tier); diagnosed by T.
  **T owns the tool, never the bug.**
- **Caused by:** `9ffbba0bd perf(A): append in place for \`s := s + x\` — Pascal
  accumulation goes linear`, then carried into the pin by
  `86da0606d chore(A): pin v299`.

## Reproduce (compiler rebuilt at HEAD)

```
$ make compiler/pascal26 && ./compiler/pascal26 test/test_managed_block_meta.pas /tmp/x && /tmp/x
FAIL grown ascii string stays ascii
managed block meta FAILED 1
```

Expected `managed block meta ok`.

## The assertion, and why it is the right one

`test/test_managed_block_meta.pas:60`:

```pascal
{ growth through the inline resize path must not lose or invent the flag }
grown := '';
for i := 1 to 300 do grown := grown + 'x';
Check(IsAscii(grown), 'grown ascii string stays ascii');
```

That comment predates the change and names the hazard exactly. `s := s + x` in
a loop is precisely the construct `9ffbba0bd` optimises, and 300 iterations
forces the buffer through at least one resize — so the new in-place path is
reached, and the kind flag is not carried across it.

Note the neighbouring assertions still pass (`concat with non-ascii is not
ascii`, and its mirror), so plain concat still maintains the flag correctly.
**It is specifically the in-place growth path that loses it.**

## Where to look

`9ffbba0bd` touches, in order of likelihood:

| file | why |
|---|---|
| `compiler/builtin/builtinheap.pas` (+104) | the managed block header and the resize itself — the flag lives here |
| `compiler/ir_codegen.inc` (+99) | emits the in-place append sequence |
| `compiler/defs.inc`, `parser.inc`, `pyparser.inc` | the recognition of the `s := s + x` shape |

The likely shape is that the resize allocates a fresh block and copies the
payload without propagating the kind bits, so the grown string inherits a
default (non-ascii) kind rather than the source's.

## Not a candidate for revert-and-forget

The optimisation is real work with a real payoff (linear accumulation instead of
quadratic), and the defect is narrow — one flag across one path. Fixing the
propagation is almost certainly smaller than losing the optimisation.

**But it is in the pin** (`v299`), so every lane building with `$(PXX_STABLE)`
has it now, not just HEAD.

## Note for whoever verifies

Rebuild first. `make compiler/pascal26` — the binary on disk may predate the
range, and this repo has recorded wrong conclusions from exactly that.

## Gate

`test/test_managed_block_meta.pas` prints `managed block meta ok`, plus
`tools/gate.sh quick`. The full assertion set matters here rather than just the
one line: the test checks that the flag is neither *lost* nor *invented*, and a
fix that force-sets ascii would pass this line while breaking the two above it.

---

## Progress — FIXED (agent-an, 2026-08-14)

**Confirmed the ticket's guess, and it was both paths, not just growth.**
Rebuilt at HEAD first (`make compiler/pascal26`, converged) and reproduced:
`FAIL grown ascii string stays ascii`.

The defect is entirely in `PXXStrAppend` (`compiler/builtin/builtinheap.pas`) —
`ir_codegen.inc` only emits a shim call, so there is **one** runtime site, not a
double case. Both of its arms threw the cached answer away:

- **in place:** called `PXXStrForgetAscii` unconditionally — "the bytes changed";
- **grow:** stamped `PXX_KIND_LEGACY or PXX_FLAG_APPENDABLE`, with a comment
  saying "the ASCII bits stay clear (unknown)".

Forgetting is *sound* but needlessly lossy, and lossy is what the test caught:
300 appends of `'x'` end unknown, and unknown reads as `IsAscii=false`. It also
defeats the point of `PXX_FLAG_ASCII_KNOWN` — every consumer rescans an
accumulated string, which is the O(n) index the flag exists to kill.

**Fix: maintain the answer, don't drop it.** New helper
`PXXStrAppendAsciiBits(oldMeta, orAll)` — the append loops already touch every
appended byte, so they now OR them (the same free trick `PXXStrConcat` uses):

| appended bytes | old block said | result |
|---|---|---|
| any >= $80 | anything | KNOWN, not ascii |
| all < $80 | KNOWN ascii | KNOWN ascii |
| all < $80 | KNOWN non-ascii | KNOWN non-ascii |
| all < $80 | **unknown** | **unknown** |

The old half is never rescanned — its answer comes from `oldMeta` — so the fix
costs one OR per *appended* byte and the append stays amortised O(1). The last
row is the one that matters: inventing ascii for a block nobody scanned is the
"wrong-and-fast" error the test's header comment names.

**Guarded that row with a new assertion** in `test/test_managed_block_meta.pas`
— appending to a `SetLength`-built (unknown-kind) string must stay unknown. The
ticket warned that a fix which force-sets ascii would pass the failing line; that
assertion is what makes such a fix fail instead.

Checked `PXXStrUnique` for the sibling hazard while here: its COW copy goes
through `PXXStrFromLit`, which does **not** stamp `APPENDABLE`, so a copy never
claims spare capacity it does not own. No second defect.

**Result:** `managed block meta ok` (full assertion set, including the two
neighbours and the new one). Self-host converges.

Needs a **re-pin** — the defect shipped in `v299`, so every lane building with
`$(PXX_STABLE)` carries it until `stabilize-fast && pin`.

## Log
- 2026-08-14 — resolved, commit PENDING-COMMIT.
