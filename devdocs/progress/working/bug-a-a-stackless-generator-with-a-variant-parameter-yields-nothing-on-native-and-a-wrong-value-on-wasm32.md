---
track: A
prio: 45
type: bug
blocked-by: []
status: working
found-by: frankwasm (while reducing bug-a-a-nilpy-generator-fails-on-wasm32)
summary: "A `generator; stackless;` routine that declares a VARIANT PARAMETER produces ZERO iterations on native x86-64 and ONE iteration with a garbage value (0) on wasm32. Six-line Pascal repro, no NilPy involved. It does NOT depend on the body reading the parameter -- a body that yields a constant fails identically -- so it is the parameter's SLOT, not its use. A Variant LOCAL is fine, an Integer parameter is fine, a Variant return is fine; only a Variant PARAMETER. Pre-existing on the pinned compiler. This is an ALL-TARGETS bug found on the native oracle, not a wasm32 one."
owner: frankS
---

# A Variant parameter makes a stackless generator produce nothing

```pascal
program p; uses slgen;
function Gen(n: Variant): Variant; generator; stackless;
begin yield n; end;
var x: Variant;
begin for x in Gen(7) do writeln('got=', x); end.
```

| | expected | native x86-64 | wasm32 |
| --- | --- | --- | --- |
| `yield n` | `got=7` | **(no output)** | `got=0` |
| `yield 9` (param unread) | `got=9` | **(no output)** | `got=0` |

**Native produces no output at all** — `for x in Gen(7)` runs zero times, so the
step function reports has-next False on its very first call. wasm32 runs the
body once and yields a value that is neither 7 nor 9.

## What was varied, and where the boundary is

Each row is the same program with one thing changed. All four controls PASS on
both targets, which is what makes the boundary a parameter's TYPE rather than
generators, Variants, or wasm32:

| shape | native | wasm32 |
| --- | --- | --- |
| `Gen(n: Variant): Variant` | **(nothing)** | **got=0** |
| `Gen(n: Variant): Variant`, body yields a constant | **(nothing)** | **got=0** |
| `Gen: Variant` with a Variant LOCAL | got=7 | got=7 |
| `Gen(n: Integer): Variant` | got=7 | got=7 |
| `Gen(n: Integer): Integer` | got=7 | got=7 |
| `Gen: Variant` yielding a literal | got=7 | got=7 |

`writeln` of a Variant is not the problem: it prints `got=7` from an ordinary
Variant outside a generator.

**The body does not have to read the parameter.** That is the load-bearing row:
a generator whose body yields a constant and never mentions `n` fails exactly
the same way, so this is about the parameter's slot region existing, not about
any read or write of it.

## Suspected site

`AssignStacklessSlots` (`compiler/pasparser_stmt.inc:~2440`) gives `tyVariant` a
TWO-word slot region and checkpoints it by blob copy:

```pascal
    if tk = tyVariant then
    begin
      SymGenSlot[i] := CurGenSlotNext;
      Inc(CurGenSlotNext, 2);
      Continue;
    end;
```

The arm makes no distinction between `skParam` and `skLocal`, and a Variant
LOCAL works — so the difference is in what happens to a PARAMETER's two-word
region at instance creation, where the caller's argument must be copied in,
rather than in the save/restore the local exercises.

Worth checking against the arm directly below it, which has this exact family's
scar tissue: `TypeIsPromoInt` used to fall through to the one-word arm and drop
the tag, and the write-up notes the promotable-int contract is *"a {tag,
payload} struct, not a machine word, so anything that must handle it asks for it
by name — an unhandled site errors instead of miscompiling"*. A multi-word
parameter is the same shape of question asked at instance-creation time.

## Why it is filed separately from the NilPy one

`bug-a-a-nilpy-generator-fails-on-wasm32-while-three-other-targets-agree` has a
similar-looking symptom (a generator parameter reads as absent on wasm32) but a
DIFFERENT signature: NilPy generators with parameters run **correctly on
native** and fail only on wasm32, whereas this fails on native first. They may
share the slot machinery; they are not the same measurement and should not be
merged on resemblance.

## Not verified

Only x86-64 native and wasm32 were measured. i386/arm32/aarch64/riscv32 are
unknown — if the mechanism is the two-word region, the 32-bit targets are the
interesting ones, because that is where the promotable-int twin of this bug
diverged.
