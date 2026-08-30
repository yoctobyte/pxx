---
slug: bug-p-a-parenless-method-reference-handles-two-of-four-receiver-spellings
track: P
prio: 45
type: bug
status: backlog
blocked-by: []
summary: "`TryParseParenlessMethodRef` (pasparser_call.inc:723) reads `obj.M` with no `@` and no argument list as a method REFERENCE, and is the single place that decision lives. It handles two receiver spellings — a class NAME and an instance VARIABLE — and there are four. A BARE name inside the class's own method (`TSel(Pick)`) and a METACLASS VARIABLE receiver (`mc: class of TSvc; TSel(mc.Pick)`) both fall through to the call path and are rejected with `wrong number of parameters in call to TSvc.Pick`. FPC accepts both. Same on pinned faf762981c3c and HEAD a9a4818ab6c8, so neither is a regression. The corpus does not need them — all 24 rtl-generics sites use the working class-name spelling — which is why this is filed rather than folded into the ticket that found it."
owner: unassigned
---

# A parenless method reference handles two of four receiver spellings

Found while verifying
[[bug-p-the-address-of-a-virtual-class-method-cannot-be-lowered]], whose own
defect turned out to be already fixed. These two arms are what the sibling check
turned up.

## Measured — binary `a9a4818ab6c8`, and identically on `pinned faf762981c3c`

| arm | receiver spelling | pxx | FPC 3.2.2 |
| --- | --- | --- | --- |
| B | class NAME — `TMethod(TSel(TSvc.Pick)).Code` | compiles, runs | ✓ |
| D | instance VARIABLE — `TMethod(TSel(s.Pick)).Code` | compiles, runs | ✓ |
| **A** | **bare name**, inside the class's own method — `TMethod(TSel(Pick)).Code` | `wrong number of parameters in call to TSvc.Pick` | ✓ |
| **C** | **metaclass VARIABLE** — `mc: class of TSvc;` then `TMethod(TSel(mc.Pick)).Code` | same error | ✓ |

Neither is a regression — both fail on the current pin too.

## Why they fall through

`TryParseParenlessMethodRef` (`compiler/pasparser_call.inc:723`) is deliberately
the ONE place this decision lives; its own comment says writing a fifth
construction site is what `root-cause-over-microfix.md` tells you to stop and
count instead of doing. Two guards keep A and C out:

```pascal
  if Tokens[TokPos].Kind <> tkDot then Exit;        { arm A has no receiver at all }
  ...
  if (rsym >= 0) and (Syms[rsym].RecName >= REC_UCLASS_BASE) and ... then
    rci := ...                                      { instance variable }
  else if (rsym < 0) and (FindUClass(...) >= 0) ... { class name }
  else
    Exit;                                           { arm C lands here }
```

A metaclass variable is a `tyPointer` whose pointee is a class, not a symbol
whose `RecName` is a class, so it misses both arms.

## The design fork — this is why it is filed rather than written

`NodeMetaclassCi` (`symtab.inc:12876`) already exists and is exactly the right
predicate. Its own comment records that the metaclass receiver was taught one
spelling per ticket as four copies of the same test, and that it exists so *"the
next spelling is added once"*. This is the next spelling.

But it takes a **node**, and at this point in `TryParseParenlessMethodRef` no
node has been built — the function is careful to allocate nothing before it is
committed, because it must be able to `Exit` without consuming tokens. So there
are three options and the choice is not the parser's to make alone:

1. **Allocate the `AN_IDENT` receiver node early** and pass it to
   `NodeMetaclassCi`. Cleanest, reuses the predicate — but it orphans one AST
   node on every `something.field` in Delphi mode that turns out not to be a
   method reference, which on a large unit is thousands of wasted nodes.
2. **Split a sym-level `SymMetaclassCi(si)` out of `NodeMetaclassCi`'s
   `AN_IDENT` arm** and call that here, with `NodeMetaclassCi` delegating to it.
   No waste, no duplication, one predicate still. **This edits `symtab.inc`,
   which is Track A ground** — so it is an A change, filed here and handed over
   rather than reached into.
3. Duplicate the three-line `tyPointer` / `PtrElemTk = tyClass` test inline.
   Cheapest, and precisely the duplication `NodeMetaclassCi` was created to end.
   Recommended against.

**Recommendation: (2).** It keeps the "added once" property the predicate was
built for, and the split is mechanical. Arm A needs no such decision — the
receiver is the enclosing method's implicit `Self`, and that fix is contained in
`pasparser_call.inc`.

## Gate

Four programs, one per row of the table, each **calling through** the taken
address rather than only asserting it is non-nil — a wrong pointer is non-nil
too. Compare against FPC; `tools/fpc_diff_probe.sh` is the oracle. Arms B and D
must stay green.
