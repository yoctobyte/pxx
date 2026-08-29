---
prio: 70
track: P
status: done
owner: pxx-a5
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 14 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_mgmt_operators.pas red at 47277dd0e52b (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-29T20:18:59Z
- **Test source:** test/test_mgmt_operators.pas test/test_mgmt_operators.expected +5

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_mgmt_operators.pas'` at 47277dd0e52b8594fdad3fb15eb2be2d2a518f41

## Range
> **The named sha `47277dd0e52b` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `47277dd0e52b`, last good `0c8459022373`, 5 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1238665/test_mgmt_operators26  [code=297424B  data=24744B  bss=75692B  procs=730]
FAIL: an array of a managed record compiled

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Coordinator measurement, 2026-08-29 (frank-coordinator) — does NOT reproduce here

**The range contains exactly ONE buildable commit.** `0c8459022373..47277dd0e52b`
is five commits; four are docs/tickets/tstate/roster. The only code-bearing one is
**`4a3c88532` — "AllocArray/AllocDynArray must clear RecName on a recycled slot"**.
Given the failure text is *"an array of a managed record compiled"*, that is a
mechanistic adjacency and not a timing coincidence, which is why it was worth
stopping a pin over.

**It does not reproduce on this host at HEAD.** With the binary pinned as v393
(`1d69760deabe`, includes `4a3c88532`), `test/test_mgmt_operators.pas` compiles
clean, runs, and its output matches `test_mgmt_operators.expected` **byte for
byte**. `.expected` contains no `FAIL` line, so a pass here is a real pass and not
an expectation that absorbed the failure.

**Deliberately NOT closed, and the reason matters.** *Now-green proves as little as
still-red until you know what changed.* Three things could each explain this and
they need different responses:

1. **Fixed by a later commit.** HEAD is past the tested sha and includes
   `8b35e88fa` (for-loop bounds) and `29e8ee52a`. If one of those closed it, the
   ticket is done and should say which.
2. **Host-specific to plexus.** This is the pattern `plexus.json` has produced
   before — a green here bounded by the machine that ran it, and nothing states
   those bounds. Note the host that filed it is not the host that cleared it.
3. **Non-deterministic.** A managed-record array touches allocation order; a red
   that appears once and clears is exactly what a slot-recycling defect looks
   like, and `4a3c88532` is a slot-recycling fix.

**What actually settles it:** the watcher re-running this job on **plexus** at a sha
at or past v393. Until then this is one host's pass against another host's fail,
which is not a verdict. Do not close it on the strength of this section.

**Note on the `track: P`** — auto-guessed from the `.pas` test source. The candidate
cause is `symtab.inc`, which is **Track A**. Re-lane before working it if the cause
is confirmed.

---

## It DOES reproduce, at HEAD, on this host — 2026-08-30 (pxx-a5)

Fixed in `compiler/pasparser_proc.inc`; self-host fixedpoint `657e79e36d75`,
`gate.sh quick` GREEN.

### Why the section above says otherwise: it measured the arm that passes

`test-core#src:test/test_mgmt_operators.pas` is not one assertion. The Makefile
target compiles `test_mgmt_operators.pas` and diffs it against `.expected` —
**and then runs three NEGATIVE rows**, each of which compiles a program that
must be REFUSED and fails if the compile succeeds:

```make
if ./$(COMPILER) test/test_mgmt_operators_array_refused.pas ...; then \
  echo "FAIL: an array of a managed record compiled"; exit 1; \
fi
```

The watcher's log tail is that exact string. The coordinator measurement checked
that `test_mgmt_operators.pas` "compiles clean, runs, and its output matches
`.expected` byte for byte" — true, still true, and about a different assertion
than the one that failed. `.expected` could not have absorbed this failure
because the failure is not in that program at all.

At HEAD (`8cb0ce6ce208`), measured before anything was changed:

| row | result |
| --- | --- |
| `test_mgmt_operators.pas` vs `.expected` | **PASS** |
| `test_mgmt_operators_array_refused.pas` | **COMPILED — must be refused** |
| `test_mgmt_operators_field_refused.pas` | refused (ok) |
| `test_mgmt_operators_copy_refused.pas` | refused (ok) |

So it is not host-specific, not non-deterministic, and not fixed by a later
commit. It is one row of four, and the three hypotheses in the section above
were all answering a question that did not need asking yet.

### The cause, and `4a3c88532` did not introduce it

`WrapManagementOpsRange` guards its refusal on `SymTR[i].RecId <> REC_NONE`,
and `SymSyncTypeRef` sets `SymTR[idx].RecId := Syms[idx].RecName`. **`RecName`
is meaningless for an array symbol** — only `AllocVar`/`AllocParam` ever write
it; an array's record id is `ElemRecName`. The refusal was reading a field that
was never about the element type, and it fired anyway because symbol slots are
RECYCLED and the stale value happened to be the right record.

`4a3c88532` cleared `RecName` on recycle, so the field became `REC_NONE`, the
whole `if` was skipped, and an array of a managed record began compiling with
an `Initialize` that never runs. That commit removed the accident this was
standing on — and **named this class in its own message**:

> *The audit found 20 more `RecName` reads guarded only by `TypeKind = tyRecord`,
> which is not a guard at all for an array symbol — that is a separate ticket,
> not this fix.*

This is one of the twenty, reached from the other side: not a read that returns
the wrong record, a read that returned the right one by luck.

**Measured, not inferred.** Rebuilt the compiler with that single line reverted:
the refusal fires again. Restored, applied the real fix, and it fires for the
right reason.

### Fix

A new `SymManagedRecId(idx)` returns `SymTR[idx].ElemRec` for an array symbol
and `SymTR[idx].RecId` otherwise, and both refusals read it. Ordinary arrays of
ordinary records are unaffected — the guard still requires an actual
`Initialize`/`Finalize` overload on the element record.

### The test could not tell a correct guard from a lucky one

That is the part worth keeping. `test_mgmt_operators_array_refused` asserts
"this is refused" and nothing more, so it passed for years on an accident and
went silent the moment the accident was cleaned up. A second arm now exists:
`test/test_mgmt_operators_global_array_refused.pas`, the same shape as a GLOBAL,
which `WrapMainBodyManagementOps` reaches through a separate call.

Both arms were measured against a rebuild with the clear reverted — **refused
there too**, i.e. the stale value covered globals as well, so the second arm is
breadth across two code paths rather than a witness the first one lacked. Said
plainly because the reverse would have been a better story and is not what the
measurement showed.

New Makefile rows checked for liveness: the refusal row pointed at a program
that does compile reports its FAIL, and the diagnostic-text row goes red against
a wrong ticket name.

### Verification

- four original rows + the new global pair: all green
- an ordinary program with global, local and dynamic arrays of plain and nested
  records compiles and runs correctly (the guard must not widen)
- `make compiler/pascal26` fixedpoint `657e79e36d75`; `gate.sh quick` GREEN

### Lane

Kept **Track P**: the trigger was `symtab.inc` (A) but the defect and the fix
are in the Pascal management-operator desugar, `pasparser_proc.inc`. No edit to
`symtab.inc`, `pasparser_decl.inc`, `pasparser_generic.inc`, or `ir.inc`.

### Still open, and it is the bigger half

The other ~19 `RecName` reads guarded by `TypeKind = tyRecord` are untouched.
`TypeKind` holds the ELEMENT kind for an array, so every one of them is a read
of a field that means nothing for the symbol it is reading — some will return
`REC_NONE` and skip work that should happen (this one), others will act on a
recycled id. That audit is
[[audit-a-typekind-tyrecord-is-not-a-guard-against-an-array-symbol]]; this
regression is the first of them to surface on its own, and it did so as a
silently-missing diagnostic rather than as a wrong answer.
- 2026-08-30 — resolved, commit PENDING-COMMIT.
