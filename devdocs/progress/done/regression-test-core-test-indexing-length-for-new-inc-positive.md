---
prio: 70
track: P
status: done
owner: trackP-worker
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/dev has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_indexing_length_for_new_inc_positive.pas red at c59796cd1e1d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-25T18:18:04Z
- **Test source:** test/test_indexing_length_for_new_inc_positive.pas test/test_indexing_length_for_new_inc_positive.expected +1

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_indexing_length_for_new_inc_positive.pas'` at c59796cd1e1d0255c93b85e67ce8cd9ea422b3e9

## Range
bad `c59796cd1e1d`, last good `10dada0b7689`, 15 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:44: error: illegal counter variable: a counted for needs an ordinal (integer, char, boolean, enum or subrange) (s)
pascal26:45: error: this value cannot be indexed — only arrays, strings and pointers can (i)
pascal26:46: error: New needs a pointer variable, not Integer (i)
pascal26:47: error: Inc/Dec needs an ordinal or a pointer, not AnsiString
pascal26:48: error: Length needs a string, an array or a PChar, not Integer
pascal26:50: error: with needs a record, class or interface — Integer has no members
pascal26:51: error: cannot assign to the result of a function call
(tail)
ok: /tmp/testmgr-scratch-2186495/test_ilfni26  [code=235935B  data=5200B  bss=43132B  procs=636]
test_scalar_misuse_is_refused_fail: FAIL - rc=1 (want rc=1, eight diagnostics on lines 44-51, no binary)
pascal26:44: error: illegal counter variable: a counted for needs an ordinal (integer, char, boolean, enum or subrange) (s)
  near: i    for s >>>   to 
pascal26:45: error: this value cannot be indexed — only arrays, strings and pointers can (i)
  near: j  i    >>>  New  
pascal26:46: error: New needs a pointer variable, not Integer (i)
  near:   New  i  >>>  Inc  
pascal26:47: error: Inc/Dec needs an ordinal or a pointer, not AnsiString
  near:   Inc  s  >>>  j  
pascal26:48: error: Length needs a string, an array or a PChar, not Integer
  near: j  Length  i  >>>  b  
pascal26:50: error: with needs a record, class or interface — Integer has no members
  near: r    with i >>> do WriteLn  
pascal26:51: error: cannot assign to the result of a function call
  near:   F1    >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## Triage — root cause

Not a Pascal bug at all in origin: **519fa45a0** (`feat(A): a file reports its LAST
mistake too — error recovery, slice 5`) added `if ErrCount > 0 then Exit;` at the
top of `CompileAST` (`compiler/ir_codegen.inc`). That is correct on its own terms
— a poisoned symbol must not reach codegen — but it means **IR lowering stops at
the first RECOVERED diagnostic**, and one of the eight refusals this test asserts
lived *only* in lowering:

    ir.inc:8746   ErrorAt(ASTLine[node], 'no operator overload found for ordering
                                          a record operand ...')

So `b := r < 1` on line 49 went silent the moment lines 44-48 had already been
reported. Measured, not reasoned: the diagnostic fires in isolation, and
disappears behind *any single* preceding recovered error — one preceding error is
enough, whichever of the five it is.

Nothing produced a binary here (`ErrCount` still halts the driver); the Makefile
recipe fails on the missing line, and the `ok:` in the log tail is the *positive*
test's binary, not this one's.

## Fix

The check is a **Pascal dialect rule** (`not CProgramMode`-guarded — the smell) that
was squatting in the shared IR, where it is both in the wrong layer and now
unreachable after any earlier diagnostic. Moved to the Pascal relational level in
`compiler/pasparser_expr.inc` (`ParseExpr`, beside the enum-vs-pointer and
enum-vs-enum FPC-parity diagnostics it belongs with), using the same
`FindOpOverload2` lookup and the same message text, and reporting through
`ErrorRecover` so the file's later mistakes (`with i do`, `F1(1) := 3`) are still
found.

The `ir.inc` arm is left in place as the backstop for nodes nobody parsed — the
same rationale its dynamic-array sibling states two arms above. It is not
touched (Track A file, Track A worker live).

Result: all eight diagnostics on lines 44-51, rc=1, no binary; the positive half
(`test_indexing_length_for_new_inc_positive`) still matches fpc's output exactly.

## Sibling left open — for Track A

The same hole applies to *every* diagnostic that exists only in IR lowering. Two
known ones sit in the same `ir.inc` binop chain and are silenced identically by a
preceding recovered error:

- `no operator overload found for record operands` (arithmetic on a record) — `ir.inc:8721`
- `arithmetic operator not supported for dynamic arrays` — the arm above it

Neither is asserted after another diagnostic today, so neither is red — but both
are now unreachable in exactly the situation a multi-error file creates. That is a
Track A question about where recovery draws the line (keep lowering for CHECKS and
skip only emission?), not a Pascal-frontend one.
- 2026-08-25 — resolved, commit 93c0ee76d9931ff84a57daf728eee930f87d3f96.
