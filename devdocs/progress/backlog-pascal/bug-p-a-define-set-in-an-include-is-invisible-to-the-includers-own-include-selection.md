---
track: P
prio: 60
type: bug
blocked-by: []
summary: "ExpandIncludes snapshots and rolls back the define table PER NESTING LEVEL, so a `{$DEFINE}` inside an include is undone before the includer's next `{$IFDEF}` is evaluated. The classic config-include pattern then loses BOTH arms silently: expansion follows the wrong `{$I}`, and the lexer — which re-evaluates over the spliced text and now DOES see the define — takes the arm whose `{$I}` was never expanded. Measured under the pinned compiler, so it is not new."
---

# A define set in an include is invisible to the includer's own include selection

```pascal
program p;
{$I setsdef.inc}          { contains {$DEFINE FROM_CONFIG_INC} }
begin
{$IFDEF FROM_CONFIG_INC}
{$I yes.inc}              { writeln('include saw the define') }
{$ELSE}
{$I no.inc}               { writeln('include selection missed it') }
{$ENDIF}
  writeln('done');
end.
```

**Prints `done` and nothing else.** Neither arm is compiled — not the wrong one,
*no* one — and there is no diagnostic.

Measured 2026-09-04 at HEAD and under `stable_linux_amd64/default/pinned`,
identical on both, so it predates the `{$CLAIM}` work that found it.

## Why both arms vanish

Every Pascal source is walked **twice**, and the two walks disagree:

1. **`ExpandIncludes`** (`compiler/elfwriter.inc`) resolves `{$ifdef}` itself, to
   decide which `{$I}` to follow. It saves the whole define table at entry and
   restores it at exit — **and it recurses into each include**, so the nested
   call's `{$DEFINE FROM_CONFIG_INC}` is rolled back the moment that include
   finishes. The includer's `{$IFDEF}` is therefore **false**, and `no.inc` is
   spliced while `yes.inc` is left as an unexpanded `{$I}` directive.
2. **The lexer** then walks the expanded text. `{$DEFINE FROM_CONFIG_INC}` is now
   *inline*, so this pass sees it: `{$IFDEF}` is **true**, and it takes the arm
   holding the bare `{$I yes.inc}` — which nobody expanded, because expansion
   went the other way.

So the active arm's content was never spliced and the spliced content sits in the
arm nobody selects. The two passes are each self-consistent and disagree, which
is exactly why nothing errors.

## Why the silence is the expensive part

`compiler/elfwriter.inc` already makes an unfindable include a **hard error**
("the old silent drop compiled with silently different configuration",
`bug-pascal-include-search-silent-miss`). This is the same failure mode one layer
up — a body silently missing rather than a file — and it is not caught by the
same guard because the file *was* found, on the walk that didn't matter.

## Shape of the fix (not attempted)

The snapshot around the recursive call is what is wrong: an include's defines are
part of the **includer's** textual state, not a scope of their own — FPC has no
such rollback. Dropping the per-nesting-level restore (keeping the outermost one,
which is what isolates one compilation unit from the next) should be the whole
change, but it changes include selection for every source in the tree, so it
wants a full tier and a census of what moves, not a quick gate.

## Re-ranked 45 -> 60, 2026-09-04

**Two sessions concurred independently, so this is a record rather than an
opinion.** frankD filed it at 45 having found it as a side-issue and ranked it
by how it arrived; frankA, reading only the write-up, said it belongs above 45
"on the silent axis alone"; frankuser confirmed neither should wait on him to
move it. The repo ranks silent above loud, and **both arms of a conditional
vanishing with no diagnostic** is the far end of that axis: the includer's pass
and the lexer's pass are each self-consistent and disagree, so nothing errors
and the body is simply not there. Compare the neighbours it sits with --
`bug-pascal-include-search-silent-miss` made a MISSING FILE a hard error for
this exact reason, one layer down; this is the same failure one layer up and was
ranked below it.

Still unowned. The cost of the fix is unchanged -- dropping the per-nesting
restore moves include selection tree-wide and wants a full tier -- so the
re-rank is about what it costs to LEAVE, not about it having got cheaper.

Found by [[feature-p-defineglobal-a-define-that-crosses-unit-boundaries]], whose
`{$CLAIM}` inherits this behaviour identically rather than working around it —
`test/units_claim/uclaim_c.pas` records the boundary.
