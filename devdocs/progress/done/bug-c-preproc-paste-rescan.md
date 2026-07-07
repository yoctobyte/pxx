---
prio: 60  # raised: also blocks tcc (ELFW ## paste + rescan)
---

# C preprocessor: ## paste result must be rescanned for further macro expansion

- **Type:** bug (cpreproc). Track C.
- **Found:** 2026-07-06 c-testsuite run.

## Failing tests
- 00201: `#define CAT2(a,b) a##b` / `CAT(A,B)(x)` — paste yields `AB`, which is
  itself a function-like macro that must expand on rescan with `(x)`. Error:
  "call to undeclared function: AB".
- 00202: paste with EMPTY argument (`P(jim,)` → `jim##<empty>`) and pasting onto
  operators (`Q(+,)` → `+##<empty>+`). Error: "++/-- operand is not an lvalue"
  → `60 + +3` mis-lexed as `60 ++ 3`?

## Fix site
cpreproc.inc: after ## paste, re-run macro replacement over the result
(C99 6.10.3.3p3); empty-arg paste = operand disappears; paste output must be
re-tokenized as ONE token only if valid, else tokens stay separate (the `+ +`
case must NOT become `++`).

## Gate
Drop 00201.c/00202.c from test/c-conformance/pxx.skip; runner green.

## Triage note (2026-07-06)
Hard: needs macro RESCAN across the expansion boundary. `CAT(A,B)` pastes to the identifier `AB`, and the `(x)` that follows in the *source* must then be consumed so `AB(x)` expands. This is the same rescan machinery as CPObjectAliasFuncMacro but for a paste result feeding a following source arg-list — a rescan-loop rework in CPExpandRange, not a patch. Also 00202 needs empty-arg paste (`a##<empty>`) + pasting onto operators without forming `++`. Defer to a focused session.


## Triage 2026-07-07
The leveled expander (CPExpandRangeForLevel/CPExpandFunctionForLevel in
cpreproc.inc) does not rescan a function-macro's OUTPUT combined with trailing
SOURCE tokens. 00201 `CAT(A,B)(x)`: CAT(A,B) expands to token `AB`, then the
following `(x)` from source must re-scan `AB(x)` as a fresh function-macro call
(→ CAT(x,y) → xy → 42). "A macro expands to a function-like macro name that then
eats following tokens" is one of the hardest cpp corners — needs the expander to
feed its output back through scanning WITH the remaining input, not expand-in-
isolation. 00202 adds empty-arg paste (`P(jim,)`→`jim##<empty>`) and operator
paste that must NOT fuse (`60 + +3` ≠ `60 ++ 3`). Focused cpreproc rework. Parked.


## Also blocks tcc (2026-07-07)
tcc's `ELFW(type)` = `ELF##64##_##type` (tcc.h:397), used as
`ELFW(ST_VISIBILITY)(sym->st_other)` (tccelf.c) — pastes to `ELF64_ST_VISIBILITY`
which must RESCAN and apply to the trailing `(...)`. Same core as 00201
`CAT(A,B)(x)`. Fixing this unblocks tcc past libtcc.c:14395 AND drops 00201/00202
from pxx.skip. Raises the value of the paste-rescan rework — the macro output must
be fed back through scanning together with the remaining input, and a pasted
identifier that names a function-like macro must expand with the following args.


## Attempt 2026-07-07 — naive splice REGRESSES (reverted); fire-condition too broad
Tried a targeted splice in CPExpandRange (cpreproc.inc): after
CPExpandFunctionForLevel, if the level's temp output ENDS in a function-like macro
name and the next source token is `(`, append that `(...)` to the temp before the
rescan. RESULT: the single-level case works (`ELFW(ST_VISIBILITY)(7)`=3, tcc's
blocker), but it REGRESSED the gate — `make test` segfault, c-conformance 198->196,
lua fail. Reverted (gate restored to 198/0). Two concrete lessons for the real fix:
1. FIRE-CONDITION TOO BROAD: "temp ends in a func-macro name + next char is `(`"
   also matches legitimate cases where that trailing name is NOT being called
   (e.g. a macro passed as an object, or the `(` belongs to the surrounding
   expression), so it wrongly consumed the following `(...)` and corrupted
   expansion. Must only splice when the pasted/expanded name is genuinely in
   call position per C rescan rules, and must respect blue-paint.
2. MULTI-LEVEL: 00201 `CAT(A,B)(x)` still failed — CAT->CAT2->AB emerges the
   func-macro name only AFTER a nested rescan, so a check on CAT's IMMEDIATE temp
   ("CAT2(A,B)") misses it. The check must run on the FULLY-expanded output, i.e.
   capture the rescan result into a temp, test its tail, splice, and re-expand —
   not the per-level temp before rescan.
So the correct fix restructures the expand→rescan flow to (a) capture the full
expansion, (b) narrowly detect a trailing function-like macro in call position vs
the following source `(`, (c) splice + re-expand once. Focused cpreproc session
with the full gate as the guard (it does catch the regressions). Backup of the
attempt was discarded; re-derive from these notes.

## IMPLEMENTATION PLAN (fresh session, 2026-07-07)

Scope: compiler/cpreproc.inc only. Fix = make a macro expansion whose FULLY-
expanded output ends in a function-like macro name consume the trailing `(...)`
from the SOURCE and re-expand (C99 6.10.3.4 rescan). Target 00201 + tcc ELFW
first; 00202 (empty-arg / operator paste) is a separate follow-on (note below).

### Root cause recap
CPExpandRange (cpreproc.inc:870) function-macro path (~983-998):
    CPActiveMacros[..]:=mi; Inc(CPActiveMacroCount);        {987-988}
    CPSetTempStrLength(level,0);
    CPExpandFunctionForLevel(mi,src,argc,level);            {991 -> CPTempStr<level> = body,args subst,## pasted}
    CPExpandRangeForLevel(level,dst);                       {992 rescans temp -> dst, IN ISOLATION}
    Dec(CPActiveMacroCount);                                {994}
    ... p := q (past the call)                              {997-998}
`dst` gets the isolated rescan; the source `(x)` after the call is copied
literally later. Output and trailing args never meet.

### The fix (5 steps)
1. New string helper (put near CPFindMacro): `CPStrTailFuncMacro(const s: AnsiString;
   var mi: Integer): Boolean` — trim trailing ws of `s`; if it ends in an
   identifier token, CPFindMacro it; return True + set mi iff that macro exists AND
   CPMFunction[mi]. (Generalizes the reverted CPTempLastIdentFuncMacro to any
   string — the KEY was checking the FULL expansion, not the per-level temp.)

2. New helper: capture a balanced `(...)` group. Given src + a start index at `(`,
   return end index just past the matching `)`, tracking nested parens (ignore
   parens inside string/char literals — reuse the quote-skip already in
   CPExpandRange's top loop).

3. Rewrite the {991-994} block:
     CPExpandFunctionForLevel(mi,src,argc,level);
     expanded := '';                     { local AnsiString }
     CPExpandRangeForLevel(level, expanded);   { FULL expansion into a LOCAL, not dst }
     Dec(CPActiveMacroCount);            { POP mi BEFORE the trailing rescan — mi's
                                          blue-paint must NOT apply to the trailing
                                          source; 00201 needs CAT free to re-expand }
     { rescan-consume-trailing: at most once — CPExpandRange recurses for depth }
     q2 := q; if src[q2]=')' then Inc(q2);      { q sits at the call's ')' }
     while (q2<=last) and (src[q2] in [' ',#9]) do Inc(q2);
     if CPStrTailFuncMacro(expanded, m2) and (not CPMacroIsActiveIdx(m2))
        and (q2<=last) and (src[q2]='(') then
     begin
       grpEnd := <capture balanced group from q2>;          { step 2 }
       combined := expanded + Copy(src, q2, grpEnd - q2);   { "AB" + "(x)" }
       reexp := '';
       CPExpandRange(combined, 1, Length(combined), level+1, reexp);
       dst := dst + reexp;
       q := grpEnd - 1;   { so the existing 'if src[q]=')' then Inc(q); p:=q' consumes it }
     end
     else
       dst := dst + expanded;
   Remove the standalone Inc(CPActiveMacroCount) duplication if needed; keep the
   push/pop balanced.

WHY this fixes both prior failures:
- Multi-level (00201): the check runs on `expanded` = the FULLY rescanned result
  ("AB"), not CAT's immediate temp ("CAT2(A,B)"). CAT->CAT2->AB now visible.
- Fire-condition: splice only when (a) the TAIL token is a function-like macro,
  (b) it is NOT currently active (blue-paint), (c) the next SOURCE token is `(`.
  Re-expansion goes through CPExpandRange (recursive, active-set-aware), so nested
  and self-referential cases stay correct.

### Test ladder (add as bXXX; bottom-up, each vs gcc)
1. object-alias -> func-macro, single level:
     #define G(x) ((x)+1)   #define A G   A(4)  == 5
2. paste -> func-macro (tcc ELFW), single level:
     #define ELFW(t) ELF##64##_##t   #define ELF64_V(o) ((o)&3)   ELFW(V)(7) == 3
3. multi-level chain (00201):
     CAT(A,B)(x) == 42  (exact 00201 body)
4. NEGATIVE / regression guards (must be UNCHANGED):
   a. func-macro name as an OBJECT, no following '(':  #define A G  int A;  (A not called)
   b. blue-paint self-ref:  #define f(x) (f)(x)  ... f(1)  (the (f)(x) already works via
      paren-name-call b171 + blue-paint; must not loop)
   c. a normal '(' that is a separate expression after a non-macro token.
5. FULL GATE (the guard that caught the last attempt): make test (self-host
   byte-identical), c-conformance (stays 198, then 200 after dropping 00201[/00202]
   from pxx.skip), lua, sqlite-threads, zlib (byte-identical — heavy macro use),
   and tcc: `./compiler/pascal26 -Ilib/crtl/... -Ilibrary_candidates/tcc
   library_candidates/tcc/libtcc.c /tmp/x` advances PAST :14395.

### 00202 (follow-on, do after 00201 green)
Empty-arg paste (`P(jim,)` -> `jim ## <empty>` -> `jim`) and operator paste
(`Q(+,)` -> `+ ## <empty>` giving `+`, and the `60 + +3` must NOT fuse into
`60 ++ 3`). Separate from the rescan splice: it's ## handling when an operand is
empty, plus a rule that pasting must not create a single token unless it's a
valid one. Handle in CPExpandFunction's ## path (cpreproc.inc ~758-815). Its own
test + drop 00202 from skip.

### Gate to close the ticket
00201 (+ ideally 00202) pass and dropped from pxx.skip; tcc libtcc.c parse past
:14395; regressions bXXX green; make test self-host byte-identical; zlib/lua/
sqlite unchanged.

## Log
- 2026-07-07 — resolved, commit a3e5c9f7.
