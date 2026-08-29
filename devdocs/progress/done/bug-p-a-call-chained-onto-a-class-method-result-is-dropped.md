---
track: P
prio: 70
type: bug
blocked-by: []
summary: "`TFactory.MakeC.Tag` — a selector chained onto a class function reached through a bare CLASS NAME — is silently dropped: the expression evaluates to the INTERMEDIATE result instead of calling the trailing method, and a member that does not exist compiles too. Measured against fpc, which answers correctly. Sibling of bug-p-a-class-method-call-keeps-the-receivers-class (fixed); this arm survives that fix. The obvious suspect (the `Exit` in ParseLValueAST's class-name arm) is REFUTED — patching it left the AST byte-identical, so the tokens are consumed elsewhere and the path is not yet located."
status: done
owner: frankB
---

# A call chained onto a class-method result is silently dropped (class-NAME receiver)

Found reducing rung 3's wall ([[feature-pascal-corpus-generics]]), alongside
[[bug-p-a-class-method-call-keeps-the-receivers-class]] — which is fixed, and
does **not** fix this one.

## Symptom: a dropped call, not a diagnostic

```pascal
b := TFactory.GetObj.Inst(14);     { fpc: 42 }
```

pxx compiles it and yields **the object pointer** — `PtrUInt(Pointer(TSvc))`
matched the answer exactly in a side-by-side probe, so the trailing `.Inst(14)`
is dropped and the expression is just `TFactory.GetObj`. A **non-existent**
member compiles too:

```pascal
b := TFactory.GetObj.NoSuchXY;     { fpc: identifier idents no member }
```

Silent wrong value, so this is a `bug-`, not compat.

Not metaclass-specific and not virtual-specific — both a metaclass-returning and
an ordinary-class-returning class function fail, virtual or not. The variable is
the **receiver**:

| chain | pxx | fpc |
| --- | --- | --- |
| `f.MakeI.Inst(14)` — instance receiver | 42 | 42 |
| `f.MakeC.Inst(14)` — instance recv, class fn | 42 *(after the sibling fix)* | 42 |
| `TFactory.MakeC.Inst(14)` — **class-name receiver** | **garbage** | 42 |
| either, split via a temp var | 42 | 42 |

## Ruled out — do not re-walk this

**The `Exit` in `ParseLValueAST`'s class-name static-method arm is NOT it.**
That arm ends `Result := mcallNode; Exit;` where both instance-reached arms
`Continue` the selector loop, which reads exactly like the bug and is the first
thing anyone will try. It was tried: replacing the `Exit` with `node := mcallNode`
so control falls into the loop left `PXXDBG=a.ast:drive` **byte-identical**, and
the behaviour unchanged. The `.Inst(14)` tokens are consumed somewhere else
entirely and that arm is not on this path. The change was reverted rather than
kept as a plausible-looking no-op.

So the next session's first job is **locating the path**, not fixing one. Start
by finding what consumes the trailing tokens — a class name at the head of a
factor may not enter `ParseLValueAST` at all. `ParseClassRecordSelectors` /
`ParseClassRefOpTail` and the call-result tail near `pasparser_lval.inc:4882`
(which is guarded on `(tk = tyClass) or (tk = tyRecord)` and passes
`ProcRetRecId[procIdx]`) are unexamined candidates.

## Repro

`TFactory.GetObj.Inst(14)` where `GetObj` is `class function ... : TSvc` and
`Inst` is any member of `TSvc`; ~20 lines, fpc-oracled. Add a member that exists
on the FACTORY but not on the returned class to check for the wrong-class
resolution the sibling ticket fixed — it must stay rejected.

## Resolved — two arms, two entries, one bug

`TClassName.ClassMethod(...)` is built in **two** places, and each returned the
bare call without applying the selector tail:

| entry | file | shape it serves |
| --- | --- | --- |
| `ParseFactorCore` | `pasparser_expr.inc` (~7262) | **expression** position — `b := TFactory.MakeC.Inst(14)` |
| `ParseLValueAST` | `pasparser_lval.inc` (~1138) | **statement** position — `TFactory.MakeC.Bump;` |

Both now apply the tail. `ParseFactorCore` routes the result through
`ParseClassRecordSelectors` when it is a class/record and a `.` follows;
`ParseLValueAST` simply stops `Exit`-ing and falls into the selector loop
already sitting eleven lines below it — the three lines above that `Exit`
had *already* computed the result's `tk` and `recName` for it.

**Why the trailing tokens vanished without a diagnostic.** They were left in the
stream, and `ParseStatementAST`'s catch-all — `pasparser_stmt.inc:6951`,
`while not (CurTok.Kind in [tkSemicolon,tkEnd,tkElse,tkUntil,tkEOF]) do Next` —
ate them. That is the same swallow documented for `F1(1) := 3;` in the comment
directly beneath it and for `GetRegistry.AddTest(X);` at `pasparser_stmt.inc:5995`,
whose remedy was to delegate the statement to the expression parser. Third
instance of one family: **a statement-level skip loop turns every unconsumed
tail into silence**, which is also the whole reason `TFactory.MakeC.NoSuchXY`
compiled — a tail that is skipped is never resolved.

## About the refutation in this ticket — it was true, and it was not the whole claim

The prior session's finding stands and I reproduced it: patching the `Exit` in
`ParseLValueAST`'s class-name arm leaves the repro byte-identical. I confirmed it
with the check the original lacked — **the compiler binary's sha256 actually
changed** (`b2dff2c3` → `f0f0f1c2`), so it was a real no-op and not a stale-binary
artifact.

But "patching this arm changes nothing" and "this arm is not defective" are
different claims, and only the first was measured. The arm *is* defective — for
a shape the repro did not contain. The repro was `b := TFactory.GetObj.Inst(14)`,
an assignment RHS, which never enters `ParseLValueAST`; the statement spelling
`TFactory.GetObj.Bump;` does, and was still silently dropping the call after the
expression arm was fixed. **A refutation is scoped to the shape that was tested.**
Same family as the rest of this bug: a no-op patch and a correct arm produce
identical evidence, so the negative result cannot distinguish them.

`devdocs/dev/normalise-dont-special-case.md`'s rule is what caught it — grep for
the sibling before closing. Here the sibling was not a second *shape*, it was a
second *entry point* for the same shape.

## Verification

`test/test_class_name_receiver_chain.pas` (+ `.expected`, wired into the Makefile
beside `test_class_method_result_type`) covers all ten spellings: method-with-arg,
parameterless method, field, deep chain, record result, two calls in one
expression, no tail at all, the parenthesised form, the temp-var split, and
statement position. **The `.expected` was generated from fpc, not hand-written**,
and the test was confirmed RED on the pre-fix `pinned` binary and GREEN after.

Rejections hold, and the sibling fix's guard with them: `TFactory.MakeC.NoSuchXY`
and a member that exists on the **factory** but not on the returned class are both
now `"no such member on this record/class"` at the right line, exit 1, no binary —
where fpc says `identifier idents no member`.

Gate: `make compiler/pascal26` fixedpoint (`converged after 1 round(s)`) +
`tools/gate.sh quick`. That gate reported one FAIL, the **FPC seed canary**, which
is **not this change**: `rparser.inc(1416,12) Error: Identifier not found
"RExprRecId"` — used at :1416, defined at :1754, no forward. Measured, not assumed:
stashing this diff and rebuilding the seed at clean HEAD reproduces it. Track R's,
filed separately.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.
