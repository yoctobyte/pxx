---
summary: "FPC: a routine declared in an inner scope HIDES the outer same-named set entirely, so a convertible argument still reaches it. pxx keeps one flat overload set, so the unit's version wins whenever the argument needs a conversion. Hiding is FPC-correct but changes resolution repo-wide"
type: decision
track: U
prio: 55
---

# Does an inner declaration hide the outer overload set, or compete with it?

- **Type:** decision — Track U. **Escalated, not guessed.**
- **Opened:** 2026-08-05
- **Raised by:** Track A, fixing
  [[bug-p-program-function-does-not-shadow-used-unit]] — two of its three
  behaviours are fixed; this is what the third turned out to be.

## The residue

After the shadowing fix, a program's own routine wins when the argument type
matches its parameter **exactly**:

```pascal
program s; uses sysutils;
function IntToStr(v: Int64): AnsiString; begin IntToStr := 'mine'; end;
begin
  writeln(IntToStr(Int64(5)));   { 'mine'  — fixed }
  writeln(IntToStr(5));          { '5'     — still sysutils' }
end.
```

FPC prints `mine` for **both**. Same with a string literal vs an `AnsiString`
variable: `Trim(a)` reaches the program's, `Trim(' x ')` does not.

## Why — and why it is NOT a tiebreak bug

sysutils declares exactly one `IntToStr`, taking `Int64`. So there is no
better-fitting overload winning fairly. What happens is:

- `5` types as `tyInteger`, so the **exact-match phase misses both** candidates;
- resolution falls through to the compatible phases, where both are equally
  convertible, and the first in registration order — the unit's — wins.

The fix already landed makes the exact-match phase prefer the current scope,
because there the two candidates tie on everything else and scope is the only
thing left to rank by. The compatible phases are different: they rank by
**argument fit**, and a better-fitting routine from anywhere *should* win. So
the same patch there would be wrong.

The real difference is structural: **FPC hides, pxx competes.**

- **FPC/Delphi:** an inner declaration hides every same-named outer one unless
  `overload` is written explicitly. So sysutils' `IntToStr` is not a candidate
  at all, and `5` simply converts to `Int64` for the only candidate left.
- **pxx:** all same-named routines form one flat set regardless of scope, and
  scope is (now) only a tiebreak among otherwise-equal candidates.

## Options

1. **Adopt FPC hiding.** Correct by the reference, and fixes the residue
   completely. But it changes resolution for *every* frontend and every unit at
   once, and it silently removes candidates that resolve fine today — code
   relying on lax cross-scope overloading would start failing to compile, or
   worse, bind elsewhere. Needs the full matrix and probably a corpus run.
2. **Hide only when the inner declaration would otherwise be unreachable** —
   i.e. if the current scope declares the name and no exact match exists
   anywhere, restrict the compatible phases to the current scope. Fixes the
   reported case with a much smaller blast radius, at the cost of a rule that
   is neither FPC's nor obviously principled.
3. **Leave it, document it.** The exact-signature case works, which covers the
   deliberate "patch an RTL routine locally" use the bug report was about, as
   long as the call site's argument types match. Cheapest; leaves a real FPC
   divergence.
4. **Adopt hiding behind `--strict-overload`**, defaulting off — consistent
   with how the repo already handles FPC-parity strictness per-feature.

## Recommendation

**Option 4**, becoming option 1 later if the corpus stays green with the flag
on. It gets FPC parity available and testable immediately without betting the
whole repo's resolution on it in one step, and it matches the existing
`--strict-case` / `--strict-overload` pattern rather than inventing a new
mechanism. Option 2 is the one to avoid — a bespoke rule here would be
invisible to anyone reading either FPC's spec or ours.

## Note on scale

This is a semantics change to shared name resolution, which bit once already
today: an earlier version of the shadowing fix preferred the LAST chain entry
and made the compiler fail to compile itself, because `FindProc` returns the
representative of an overload set and the parser reads its signature to decide
whether `EmitAsmX64([...])` is an open array or a set. Resolution changes here
are not local.
