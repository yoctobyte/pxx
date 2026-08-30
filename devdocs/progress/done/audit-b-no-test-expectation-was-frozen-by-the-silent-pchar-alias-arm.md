---
track: B
prio: 30
type: chore
blocked-by: []
summary: "AUDIT, negative result: no recorded expectation could have been frozen wrong by the silent arm of the Pointer-alias defect. Exactly 8 aliases-of-an-existing-pointer-type exist repo-wide across 1746 files; 7 alias Pointer/PRec and are never indexed, and the single indexed one is the regression test written AFTER the fix, whose expectation is derived from its own source line. The 4 large-integer Makefile expectations are independently derivable — 25! and the alloca sum confirmed against gcc."
status: done
owner: frankB
---

# Audit: could the silent `PChar`-alias arm have frozen a wrong test expectation?

- **Type:** chore (audit) — **Track B**.
- **Run:** 2026-08-30 by frankB against pin `53800fbeb0b66e11`.
- **Result: NO. Nothing to fix.**

## Why the question was worth asking

[[bug-p-a-pointer-type-alias-rejects-a-class-instance-that-plain-pointer-accepts]]
had three arms. Two were loud (a deref that did not compile, an overload that
took Track B's gate red). The third was silent: `c[i]` through an alias of
`PChar` printed **`378951523` instead of `pxx`**, and did so *for the life of
the defect*.

A silent wrong value has a second-order hazard that a loud one does not. Test
expectations here are frequently **captured from a program's output** rather
than derived from its source — `tools/expect_same.sh <name> "$(...)" "<value>"`.
Any expectation captured while this arm was live would have recorded the garbage
as correct, and would then *defend* the broken behaviour after the fix landed.
That is the failure this audit is looking for: not a bug that is still present,
but a wrong answer preserved in a test.

**This was read-and-judge, not a grep for a string.** A frozen expectation looks
exactly like a correct one; the only way to tell is to derive the value from the
source independently and compare.

## Method and scope

Scanned **1746 files** — `lib/**`, `test/**`, `examples/**`, `compiler/**`
(`.pas` and `.inc`).

The first pass was wrong and is worth recording. Searching for "pointer aliases"
matched 180 declarations, but nearly all were of the form `PRec = ^TRec` — that
**defines** a new pointer type, it does not alias an existing one. The defect
needs `X = PChar`: an alias whose element type is *inherited* from the aliased
type, which is the thing that was being resolved wrongly. Conflating the two
inflated the search 22x and would have buried the answer in false positives.

## Result — the construct is essentially unused

Aliases of an **existing** pointer type, repo-wide, complete list:

| file | alias | indexed? |
| --- | --- | --- |
| `lib/rtl/tls.pas` | `TTlsConn = Pointer` | no |
| `lib/pcl/tk.pas` | `PTclInterp = Pointer` | no |
| `lib/pcl/historic/gtk3.pas` | `PGtkWidget = Pointer` | no |
| `test/units/uptralias.pas` | `SslPtr = Pointer` | no |
| `test/units/uptralias.pas` | `PRecA = PRecX` | no |
| `test/test_pointer_alias_identity.pas` | `LocalP = Pointer` | no |
| `test/test_pointer_alias_identity.pas` | `LocalPR = PRec` | no |
| `test/test_pointer_alias_identity.pas` | `LocalPC = PChar` | **yes — `lc`** |

Seven of the eight alias `Pointer` or a pointer-to-record and are never indexed;
`Pointer` has no element type, so indexing it is not legal in the first place.
**No library, example or application code uses the construct at all.**

The single indexed use is in `test/test_pointer_alias_identity.pas` — the
**regression test for this very defect**, written against the fixed compiler,
i.e. after the arm was closed. Its expectation cannot have been captured from a
broken build because no broken build ever compiled it.

And that expectation is **derived, not captured**. The source says:

```pascal
  lc := 'pxx';
  writeln('pchar ', lc[0], lc[1], lc[2]);
```

and the Makefile expects the substring `pchar pxx` — which follows from the
assignment above by inspection. A captured expectation would have read
`pchar 378951523`.

## Second pass: the expectations that would LOOK like frozen garbage

Independent of the alias question, a value frozen from a broken build tends to
surface as a bare large integer where text or a small number belongs. All four
such expectations in the `Makefile`, judged rather than grepped:

| expectation | value | verdict |
| --- | --- | --- |
| `test_promoint_overflow26` | `15511210043330985984000000` | **derived** — it is exactly `25!`, confirmed |
| `test_alloca26` | `7088718` | **derived** — see below |
| `c_widths26` | `5000000000` | **derived** — a deliberate >32-bit width constant |
| `c_typedef26` | `5000000000` | same |

`test_alloca26` was the only one not self-evident, so it was checked against two
independent sources rather than reasoned about: re-implementing
`test/test_alloca.c`'s arithmetic in Python gives **7088718**, and building the
same file with **gcc** and running it prints **7088718**. Three sources agree.

## Conclusion

**No expectation was frozen, and there is nothing to change.** The silent arm
was real and did produce wrong output, but the construct that triggers it is
used in exactly one place in the repository, and that place postdates the fix.

## Scope limit, stated so this is not over-read

This audit covers the silent arm **as characterised**: a wrong value read by
indexing through an alias of a pointer type. It is not a general audit of
captured-vs-derived expectations across the Makefile, which is a much larger
question and remains open. What it establishes is that *this* defect left no
residue in the test suite.

## Worth keeping

The general hazard is real even though this instance is clean: **an expectation
captured from output records whatever the compiler did that day, including a
bug, and then defends it.** Where a value is derivable — a factorial, an
arithmetic sum, a string literal the source assigns two lines earlier — deriving
it costs one minute and removes the failure mode entirely. `test_alloca26` is
the model: its value is reproducible from the source by anyone, in any language,
without running our compiler at all.

## Log
- 2026-08-30 — resolved, commit f7e320b17.
