---
slug: bug-a-a-const-and-a-routine-of-the-same-name-silently-resolve-to-the-const
track: A
prio: 70
type: bug
status: done
created: 2026-09-02
found: 2026-09-02
found-by: frankC
owner: frankC
commit: 9d4bda60b
blocked-by: []
summary: "Pascal is case-insensitive, so `const PYITER_MAP = 4` and `function pyiter_map(...)` in one unit are ONE identifier. compiler/builtin/pylib.pas had FOUR such pairs, and `pyiter_map(key, v)` folded to the const, ANSWERED 4 and threw the arguments away -- silently, on every target. i386 alone objected, indirectly: it refuses to load a const symbol, so every program pulling in pyeval was unbuildable there. FIXED both ways -- the tag family is renamed PYITER_K_* so the collision is structurally impossible, and calling a const is now a refusal that names which way it resolved."
---

# A const and a routine of one name silently resolve to the const

## The trail, because none of it started here

`examples/tk/uses_tkinter_and_configparser` was the one example failing on every
cross target. Its i386 cause read:

```
pascal26:5563: error: target i386: symbol kind not supported yet (load)
  in: ./compiler/builtin/pyeval.pas
```

which names nothing. The branch one `if` BELOW it in the same procedure already
knew to name the symbol, and carries a note saying why: *"the reported line
belongs to the UNIT being parsed rather than to the file you invoked, so there
is nothing to grep for."* That fix had been made once and this branch was left
out. Naming it took one edit and turned the message into:

```
target i386: symbol 'PYITER_MAP' is a CONST symbol in load position
```

...at `Result := pyiter_map(key, v);`.

## The defect

`pylib.pas:103` declares `PYITER_MAP = 4`, a `TPyIter.FKind` tag.
`pylib.pas:1423` declares `function pyiter_map(key: Pointer; const v: Variant)`.
**Pascal is case-insensitive: those are the same identifier.** Four of the tags
collided with their own constructors — `pyiter_map`, `pyiter_filter`,
`pyiter_zip`, `pyiter_enum`.

pxx resolved the call to the CONST, folded it to a literal, and **dropped the
argument list**. Minimal form:

```pascal
const MY_THING = 4;
function my_thing(a: Integer): Integer;
begin my_thing := a * 100; end;
...
r := my_thing(7);        { was: 4 }
```

Every target. x86-64 built it happily; only i386 refuses to load a const symbol
and so was the only one that said anything, about something else.

FPC rejects the declaration pair outright — *"overloaded identifier MY_THING
isn't a function"* — so no parity check could have found this.

## Fixed at both ends, because one of them is not enough

**The library.** The whole `PYITER_*` tag family is renamed `PYITER_K_*` (13
constants, 59 occurrences, confined to `pylib.pas`). The prefix rather than four
renames, because the trap is STRUCTURAL: any kind added later whose name matches
its constructor's walks into it again, and the failure is a plausible small
integer. The rule is written where the family is declared.

**The compiler.** A const followed by an argument list is now a refusal naming
which way the identifier resolved and what to do. We keep ACCEPTING the
declaration pair — a tag constant beside its constructor is a real thing to
write, and accepting what FPC rejects is not a defect — but a call of the const
is a mistake under any reading, and the rule is to leave the mistake visible
rather than to answer it.

## Verification

- `test/test_const_shadows_routine_fail.pas` — negative: must not compile, and
  the message must say the const won.
- `test/test_typed_const_is_callable.pas` — **the positive control, and the
  reason the guard is narrow**: a PROCEDURAL-typed const (`const F: TFn =
  @Triple;` then `F(5)`) genuinely IS callable and must keep working. Verified
  in pxx and in FPC before the guard was written; both answer 15. Without this
  row, "consts cannot be called" would look like a safe blanket rule.
- NilPy `map` / `filter` / `map(int, ...)` match the CPython oracle before and
  after (they ran through the `_i` entries, not the shadowed ones).
- `examples/tk/uses_tkinter_and_configparser` builds for i386 — the last of that
  demo's four causes.
- `tools/gate.sh quick` GREEN with the tree dirty.

## What it says about the shape

Third silent-wrong-answer in this session whose only witness was a REFUSAL on a
minority backend: the by-value record, the `Write`-method arity, and this. The
x86-64 path has the fewest guards because it is the one everything is developed
on, which is exactly backwards. **A refusal on a cross target is worth reading
before it is worth ranking.**
