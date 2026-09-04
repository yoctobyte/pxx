---
track: P
prio: 60
type: bug
blocked-by: []
summary: "FIXED 2026-09-04. ExpandIncludes snapshotted and rolled back the define table PER NESTING LEVEL, so a `{$DEFINE}` inside an include was undone before the includer's next `{$IFDEF}` was evaluated, and the classic config-include pattern lost BOTH arms silently: expansion followed one `{$I}` and the lexer — re-evaluating over the spliced text, where the define now sits inline — took the other. Only the outermost call restores now. A SECOND two-walk disagreement was found and fixed alongside it: the pre-pass's brace-comment scanner was missing the lexer's NestedComments arm, so the two walks disagreed about where a comment ends."
status: done
owner: frankS
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

Found by [[feature-p-defineglobal-a-define-that-crosses-unit-boundaries]], whose
`{$CLAIM}` inherits this behaviour identically rather than working around it —
`test/units_claim/uclaim_c.pas` records the boundary.

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

Was still unowned when that was written; frankS took it the same day and it
is fixed below. The cost of the fix was judged unchanged -- dropping the per-nesting
restore moves include selection tree-wide and wants a full tier -- so the
re-rank is about what it costs to LEAVE, not about it having got cheaper.

## Fixed 2026-09-04 (frankS)

`ExpandIncludes` now restores the define table only when `IncExpandDepth = 0`.
`IncExpandDepth` was already incremented and decremented around the recursive
splice, so it is exactly the discriminator wanted and no signature changed. The
outermost restore stays — it is what isolates one compilation unit from the
next, which is the whole reason `{$CLAIM}` had to be invented.

The repro now prints `include saw the define` / `done`, matching fpc 3.2.2.

**Census of what moves** (the ticket asked for one). The population is `.inc`
files that actually set a define: **0 in `lib/`, 0 in `examples/`, 2 in `test/`**
(`cond_comment_guard.inc`, `incdir_nested/n_level3.inc`), both already in
test-core. The probe also found the control I had just planted
(`test/define_in_include_sets.inc`), so the zero is a measured absence rather
than a grep that was never live. `compiler/` is covered by the self-host
fixedpoint, which converged.

Gate: `make compiler/pascal26` converged, `gate.sh quick` GREEN with the FPC
seed canary live (verdict read from the log, not the wrapper). The full tier
this ticket asked for was not run: CLAUDE.md supersedes ticket `Gate:` lines,
and the census above bounds the blast radius to files the quick tier already
compiles.

## A second bug found on the way, also fixed

The build died with `cannot open include file (no.inc)` while I was writing the
comment above — naming a file that existed only *inside* that comment. The pin
fails identically, so it predated this work.

`lexer.inc`'s brace-comment scanner nests on `(NestedComments or next = '$')`;
`elfwriter.inc`'s had **only the second half**. In a comment nested two deep the
inner plain open-brace was not counted, its close-brace decremented a level it
never opened, and the pre-pass left the comment early — reading the rest as live
directives while the lexer still read comment text. The sibling arm of a double
case, never grepped for when the lexer half landed.

**The first cut of that fix was wrong and only a probe caught it.** Honouring
`NestedComments` made the pre-pass read a global it does not maintain
(`PasInitDefines` leaves it `True`), so a `{$MODE DELPHI}` source got FPC nesting
during expansion and Delphi nesting during lexing: `dm2.pas` printed
`include expanded` under fpc *and under the pin*, and `undefined variable` under
my build. The same two-walk disagreement, pointed the other way. The pass now
tracks `mode` and `nestedcomments` itself and restores the global at the
outermost exit, beside the define table. Both directions carry a test.

The invariant this all sits on, as frankD framed it: the defect is never the
number of traversals — pass1/pass2 is a duplicated walk we want — it is **a walk
carrying a side effect the other walk cannot see, or vice versa**. Three
instances here, all in the same procedure: the define rollback, the comment-end
disagreement, and the mode-dependence of the second.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 824e95953.

## The census above was reported too narrow — corrected 2026-09-04

frankD's objection, and it is right about what was *written* here: the
define-setting census bounds finding (1) only. Findings (2) and (3) change the
comment scanner and mode handling in a pass that runs over EVERY Pascal source,
so their population is sources carrying a brace comment — **2117 of 2265** in
`compiler/ lib/ examples/ test/`, not the 2 include files named above.

That measurement was run before landing and then not written down here, which is
the actual failure: a verification claim scopes to what was checked, and this
record understated it. The instrument compares where a brace comment ENDS under
the old rule (nest on `{$` only) against the new one (nest on any `{`), and
reports the disputed span:

- **761 comments end at a different position.**
- **Four** have any directive in the disputed span:
  `test_pascal_nested_comment_directive.pas:18` and
  `test_pascal_delphi_mode_comment_include.pas:19` are the two fixtures added
  here — the live controls, so the count is not a dead probe;
  `test_pascal_macro_comment_nesting.pas:29` is Delphi-mode and passes (the
  scanner assumes `NestedComments`, so it over-reports there — conservative in
  the safe direction); `lib/rtl/palparallel.pas:4` is `{$threadsafe on}` quoted
  in prose, which this pass does not act on in either reading.

**The stronger instrument is frankD's, not this one.** He swept all 2265 sources
HEAD-vs-pin with the same list and flags: **HEAD 558 fail, pin 632**. Six sources
the pin compiles and HEAD refuses; five are deliberate must-not-compile tests
(two of them the `{$FATAL}` pair added this session, which assert `! $(COMPILER)`
and `! test -e`). **Zero regressions attributable to this change.** The sixth was
`test_hint_directive_on_a_generic_type` and belonged to `771b157a6`, not here:
`library` is an FPC hint directive (`type T<X> = class end library;`) that had
been reserved as a keyword.

So the full tier was still not needed for this change — but that conclusion is
now carried by an empirical sweep over the right population rather than by a
static census over the wrong one.
