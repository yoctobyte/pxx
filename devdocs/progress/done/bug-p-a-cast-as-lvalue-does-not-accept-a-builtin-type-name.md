---
track: P
prio: 50
type: bug
blocked-by: []
summary: "`TObject(p^) := o` compiles, but `Pointer(p^) := q` is `error: undefined variable (Pointer)` — the cast-as-lvalue path resolves a class/user type name but not a builtin one, so in lvalue position `Pointer` is parsed as a variable. Blocks `TFPGInterfacedObjectList` in real FPC `fgl.pp`."
status: backlog
owner: —
---

# A cast-as-lvalue accepts a class type name but not a builtin type name

**RESOLVED 2026-08-26.** One shared body, one lookup. The fgl rung went 3/7 to
6/7 -- see Outcome at the end, including what the last driver really hits.

- **Type:** bug (Pascal frontend — lvalue typecast name resolution)
- **Track:** P — tag: compat
- **Found:** 2026-08-25, bringing up the fgl rung of the Pascal real-world
  corpus ladder ([[feature-pascal-corpus-fgl]]).

## Measured (pxx `stable_linux_amd64/default/pinned`, VERSION 374; oracle FPC 3.2.2)

| statement | FPC 3.2.2 | pxx |
| --- | --- | --- |
| `TObject(p^) := o;` | compiles, runs | compiles, runs |
| **`Pointer(p^) := q;`** | compiles, runs | **`error: undefined variable (Pointer)`** |
| `Integer(x) := 3;` (no deref) | compiles | `error: cast-as-lvalue statement requires a pointer deref inside the cast` — a *different*, deliberate diagnostic |
| `a := Pointer(b);` (same cast, rvalue) | compiles | compiles |

```pascal
program t;
var a, b: Pointer; p: Pointer; i: Integer;
begin
  i := 5; b := @i; a := nil; p := @a;
  Pointer(p^) := b;                { pxx: undefined variable (Pointer) }
  writeln(Assigned(a));
end.
```

## Root shape

pxx *has* a cast-as-lvalue feature — `TObject(p^) := o` works and there is a
dedicated diagnostic for the no-deref form, so the statement shape is
recognised. What fails is **name resolution in lvalue position**: a builtin type
name is looked up as a variable, not as a type, and the same name resolves
correctly one line up in rvalue position. One concept, two lookup paths, one of
them broken — `devdocs/dev/normalise-dont-special-case.md`. Grep for the
sibling: every builtin type name (`Integer`, `PtrUInt`, `Byte`, `Char`,
`Pointer`, `Boolean`) is likely affected in this position, not just `Pointer`.

## Why it matters (the real-world hit)

`rtl/objpas/fgl.pp:1189`, `TFPGInterfacedObjectList.CopyItem` — the refcounted
interface container's whole item-copy path:

```pascal
procedure TFPGInterfacedObjectList.CopyItem(Src, Dest: Pointer);
begin
  if Assigned(Pointer(Dest^)) then
    T(Dest^)._Release;
  Pointer(Dest^) := Pointer(Src^);      { <-- rejected }
  ...
```
Casting a pointer through an lvalue is standard practice in low-level container
and RTL code, so this is not an fgl quirk.

## Repro / gate

`test/fgl/ifclist.pas` is the corpus driver, currently skip-listed against this
ticket in `test/fgl/pxx.skip`. Remove the skip line when fixed and
`tools/run_fgl_corpus.sh` enforces the pass against the recorded FPC 3.2.2
oracle output.

Gate = `make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick`.

## Links
Rung: [[feature-pascal-corpus-fgl]] · umbrella
[[feature-pascal-corpus-expansion]]


---

## Outcome (2026-08-26)

The ticket's "grep for the sibling" instruction was the right one and the survey
it asked for is what shaped the fix. Measured, every builtin type name as a
cast-as-lvalue target:

| target | before | after |
| --- | --- | --- |
| `Integer` `LongWord` `Char` `Boolean` `Byte` | works | works |
| `Int64` `Pointer` `PtrUInt` `AnsiString` | **`undefined variable`** | works |
| `String` | **accepted, wrote NOTHING** | works |
| `TObject` and class names | works | works |

The split is exact and explains itself: the five that worked are the ones that
lex as KEYWORD tokens, and the cast-as-lvalue code lived inline in their `case`
arm. Everything spelled as an identifier never reached it and fell through to the
variable lookup.

`String` was the worst of the three outcomes. It did not error -- it parsed as
something else and stored nothing, silently, which is how `list_str` read back
empty and `map_str` raised `EListError` on a key it believed it had stored.

## The fix, and why not a sixth name

The arm's body is now `ParseCastAsLValueStore`, called from three places: the
keyword-token case, a new `tkString_T` case, and a new identifier arm that asks
`BuiltinTypeNameTk` -- the SAME function the expression side uses to resolve a
builtin type name. Not a new list of names.

That mattered because this is the third time this shape was fixed here one name
at a time. The C4 pointer-alias arm a few lines below carries a comment saying
so about builtin POINTER names (`PInteger(p)^ := 42` was `undefined variable
(PInteger)` while the same cast one line up compiled), and the expression site
had its own round before that. Three rounds of "add the missing name" is what
`root-cause-over-microfix.md` means by a design flaw; the shared lookup is the
answer that does not need a fourth.

The identifier arm is guarded by `FindSym(name) < 0` so a variable actually named
`pointer` still parses as a variable -- the lookup order the rest of the file
promises.

Pinned in `test/test_cast_as_lvalue_builtin_names.pas`, keyword rows included:
their body moved out from under them, so "nothing else changed" needs evidence.

## The fgl rung: 3 pass -> 6 pass

`list_str.pas` and `map_str.pas` now PASS -- the read half was
[[bug-p-a-string-typecast-is-a-conversion-and-not-a-cast]] earlier the same day
and this is the write half. `objectlist.pas` was already passing.

`ifclist.pas` COMPILES now: `Pointer(Dest^) := Pointer(Src^)`, the line this
ticket is named for, is accepted and correct. It then SEGFAULTS at runtime, which
nobody could see while it failed to build. Narrowed and filed separately as
[[bug-p-an-interface-retrieved-from-a-generic-container-segfaults]]: the plain
`specialize TFPGList<IFoo>` is enough to reproduce (`f := l[0]` crashes with
`Add` and `Count` both correct), and fgl's `CopyItem` body written out by hand
against real `IFoo` variables matches fpc line for line -- so the interface
primitives work and it is their use through the GENERIC that does not.
