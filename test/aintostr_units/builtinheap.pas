{ SPDX-License-Identifier: MPL-2.0 }
unit builtinheap;
{ A DELIBERATE IMPOSTOR, and the only reason it exists is to make a NEGATIVE
  number reach a compiler diagnostic.

  The subject under test is AIntToStr (compiler/util.inc), the compiler's own
  IntToStr, which returned the EMPTY STRING for every n < 0 until 2026-08-21
  (bug-a-aintostr-returns-empty-for-negative-numbers). It has ~40 call sites and
  not one of them can currently pass a negative: they all print a count, an
  index, a parameter number or a version. That is precisely why the bug lived
  for so long, and it is also why testing the fix takes a prop.

  The RTL layout guard in pasparser_proc.inc is the one diagnostic a user can
  drive to a negative through supported CLI surface. It fires when a linked
  builtinheap declares a PXX_RTL_LAYOUT_VERSION different from the one the
  compiler emits for, and it prints that unit's number verbatim. `-Fu` is
  searched BEFORE the compiler's own RTL directory (compiler.pas appends the
  default last, on purpose, so a user override wins), so pointing -Fu here
  substitutes this stub for the real builtinheap and the guard prints whatever
  number is selected below.

  Nothing else in this unit needs to be real: Error() halts the compile at the
  guard, which is the statement right after the unit body is parsed, so the
  stub is never linked and its emptiness is never observed.

  If that guard is ever reworded or removed, THIS TEST IS NOT THE THING THAT
  BROKE — re-point it at whatever diagnostic can then carry a negative, or
  delete it if none can. }
interface
const
{$ifdef LAYOUT_LOW}
  { Low(Integer). The reason the fix accumulates digits on the negative side
    rather than negating first: |Low| has no positive representation, so
    `n := -n` leaves it unchanged and the loop never terminates. A fix that
    handled -1 and -12345 correctly can still hang here. }
  PXX_RTL_LAYOUT_VERSION = -2147483648;
{$else}
{$ifdef LAYOUT_ZERO}
  { Zero takes the separate branch (the digit loop cannot emit '0'), so it is
    the case a sign-handling rewrite is most likely to drop. }
  PXX_RTL_LAYOUT_VERSION = 0;
{$else}
{$ifdef LAYOUT_ORD}
  PXX_RTL_LAYOUT_VERSION = -12345;      { an ordinary multi-digit negative }
{$else}
  PXX_RTL_LAYOUT_VERSION = -1;          { the single-digit boundary case }
{$endif}
{$endif}
{$endif}
implementation
end.
