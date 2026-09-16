---
summary: "RESOLVED 2026-09-16: `static __thread int f;` at block scope compiled to an ORDINARY STACK LOCAL — the dispatcher read `static`, consumed it, tested for a type token, met `__thread` instead, and fell through with the static-ness already discarded. Silent wrong value, SINGLE-THREADED, on x86-64, the default target: pxx returned 4388880/4388881/4388882 against gcc's 1/2/3. Nothing to do with threads; the `__thread` merely stood in the way of the `static`. Fixed by replacing the `static` special case with an order-independent storage-class loop over a deliberately NARROW set (not CIsTopLevelSkipIdent, which also holds `asm` and `_Static_assert` — legal statements at block scope)."
type: bug
track: C
prio: 70
status: done
created: 2026-09-16
found-by: frankuser
owner: frankb-56
tags: [c-frontend, storage-class, silent-wrong]
blocked-by: []
---

# A block-scope `static` is dropped when a storage class precedes the type

## The defect

`cparser.inc`, `ParseCStatementAST`. The old shape:

```pascal
if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'static') then
begin
  Next;
  if IsCTypeTok then
  begin
    CLocalStaticDecl := True;   { ...only on this path }
```

`static __thread int f;` reads `static`, consumes it, tests `IsCTypeTok`, meets
`__thread` — and **falls out of the branch with `CLocalStaticDecl` still False
and the `static` already thrown away.** The declaration then parses as an
ordinary local.

**This is not a thread-local bug.** Any storage class standing between `static`
and the type does it; `__thread` is simply the one someone wrote.

## Measured 2026-09-16, single-threaded, x86-64, default target

`static __thread int f; f++; return f;` called three times:

| | result |
| --- | --- |
| gcc -O2 | `1 2 3` |
| pxx before | `4388880 4388881 4388882` |
| pxx before, with `= 0` | `1 1 1` |
| pxx before, plain `int f = 0;` (suspect control) | `1 1 1` |
| pxx before, `static int f;` (working control) | `3 2 1` |
| **pxx after** | `1 2 3` |

The `= 0` row reading **identically to a plain stack local** is what identified
the mechanism. The clincher was calling through a recursion that pushes a
512-byte frame: the counter **restarted**, which a static cannot do.

## Two findings worth more than the fix

**A ONE-CALL PROBE CANNOT SEE THIS, AND MINE DIDN'T.** The first investigation
recorded `static __thread int f = 0;` as **working**, because it called the
function once and got 0 — which is also what a fresh stack local holds. A
discarded static and a real static agree on the first call and diverge only
from the second. That is the *"if the machinery did nothing at all, would this
row still pass?"* question, answered yes, in the one shape where the honest
answer looks like a pass.

**AND THE NO-INITIALISER ROW CAN PASS ON THE BROKEN COMPILER BY LUCK.**
Standalone, the unfixed compiler returned `4388880…` for `static __thread int
f;`. Inside the regression test's larger program the same declaration returned
`1 2 3` — the wrongly-chosen stack slot happened to hold 0. **Uninitialised
stack memory is zero far too often for a no-initialiser row to discriminate.**
The test keeps that row because it is the shape users write, and rests its
verdict on the seeded and deeper-frame rows instead.

## The fix

One order-independent loop over the storage classes that may precede a local
type, recording whether `static` was among them.

**The set is deliberately narrow and is NOT `CIsTopLevelSkipIdent`.** That set
also holds `asm`, `__asm__`, `_Static_assert` and `__attribute__`, every one of
which is a legal **statement** at block scope — skipping them here would eat an
`asm(...)` statement before anything could parse it. `extern` is left out on
purpose: legal at block scope, not handled today, and adding it is a behaviour
change with no measurement behind it.

## Verified

`test/c_block_static_survives_a_storage_class.c`, wired into `test-core`, six
rows, **every one called more than once**:

    pxx     block static survives a storage class: 6 rows OK   rc=0
    gcc     block static survives a storage class: 6 rows OK   rc=0
    PINNED  FAIL zero / FAIL seed / FAIL deeper / FAIL back    rc=1

`__thread static` (specifier before `static`) is **not** a row: gcc refuses it
(*"'__thread' before 'static'"*) and pxx accepts it. Us accepting what gcc
rejects is not a defect, but a row gcc cannot compile would cost the file its
oracle. The C11 `static _Thread_local` spelling is a row instead.

Controls re-run and unmoved: block-scope `static` aggregates (sqlite's
`static sqlite3_vfs aVfs[]` shape — `1 x 2 y same=1`, matching gcc) and
block-scope inline `asm`.

## Residual, not this ticket

Function-scope `__thread` now has **correct storage** and is still **one copy
shared by every thread** — correct single-threaded, wrong under threads, with no
diagnostic. That belongs to
[[bug-c-thread-local-storage-still-shares-one-copy-off-x86-64-and-a-warning-is-all-that-stands-there]].

Found separately while probing: **`_Static_assert` at block scope is refused**
(`call to undeclared function: _Static_assert`), identically on HEAD and on the
pin, so pre-existing and unrelated. Filed as
[[bug-c-_Static_assert-is-refused-at-block-scope]].

Gate: `make compiler/pascal26` converged after 1 round (24cf75e4ff7d);
`tools/gate.sh quick` GREEN.
