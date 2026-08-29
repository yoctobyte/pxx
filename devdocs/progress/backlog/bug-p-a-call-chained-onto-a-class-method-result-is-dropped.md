---
track: P
prio: 70
type: bug
blocked-by: []
summary: "`TFactory.MakeC.Tag` — a selector chained onto a class function reached through a bare CLASS NAME — is silently dropped: the expression evaluates to the INTERMEDIATE result instead of calling the trailing method, and a member that does not exist compiles too. Measured against fpc, which answers correctly. Sibling of bug-p-a-class-method-call-keeps-the-receivers-class (fixed); this arm survives that fix. The obvious suspect (the `Exit` in ParseLValueAST's class-name arm) is REFUTED — patching it left the AST byte-identical, so the tokens are consumed elsewhere and the path is not yet located."
status: backlog
owner: unassigned
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
