---
type: bug
track: N
prio: 80
status: done
slug: bug-n-a-module-name-rebound-to-another-type-inside-a-block-stores-raw
summary: "A module-level name first bound to a number and rebound to a string or an object INSIDE a for/while/if block was stored RAW into the number's slot. `x = len(a); x = \"s\" * 3; print(x)` in a module-level loop printed 6291688 (the string's address) where CPython prints `sss`, and leaked the string every pass. REFUSED at compile time since 2026-10-02 (frankuser), naming the `x: Any` annotation that makes it work. The real fix, making the module pre-pass read these bindings, is still open."
---
# A module name rebound to another type inside a block is stored raw

## What happened (pin v452, 53dbb01c15)

    a = [1, 2, 3]
    for k in range(2):
        x = len(a)
        x = "s" * 3
        print(x)          # CPython: sss    pxx: 6291688, 6291728

`--dump-ir` shows it: `x` is a 4/8-byte INT slot (`store_sym ... tk=1`), and
the string concat result is stored into it with no conversion. A list in the
same place (`x = list(zip(...))`) printed as an integer and leaked the list and
its storage every pass. That was how it was found: a leak census of zip over
five or more inputs leaked 11 objects per pass, but only in a program where some
OTHER branch had bound `x = len(...)`.

It is only the MODULE level, and only inside a block:
- Straight-line module code is right. The module pre-pass trial-parses every
  depth-0 binding, so `x` widens to a variant.
- A def body is right. PyCollectLocalsAST trial-parses every binding.
- Inside a module-level block, PyCollectModuleLocalsAST reads only a few
  no-parse shapes: a literal, a known name, a subscript or field of one, a
  constructor call. It cannot trial-parse there, because a name the pre-pass
  has not seen (a for target, say) makes Error() Halt the compile. `len(a)` and
  `"s" * 3` are not in that list, so the real parse's FIRST binding decided the
  slot by itself.

Earlier tickets fixed this one shape at a time (float literal, subscript, field
read, constructor). This is the general case of the same hole.

## What landed (2026-10-02, frankuser)

`PyRefuseUnwidenedModuleRebind` (pyparser.inc), called at the real parse's
plain-assignment store, at module scope only. It refuses a binding when the
slot holds one storage family (number, string or object) and the incoming
value is a STRING or an OBJECT from another family. The message names the
variable and the fix: `x: Any = ...` on the first binding, which is verified to
work.

A NUMBER arriving is deliberately not checked. An operator over two objects is
statically typed as a number whether or not it is one, and
`r = {"a": 1} - {"b": 2}` (which correctly raises TypeError at run time,
test_nilpy_set_ops.npy) was the one false positive found. That leaves a number
stored into an object or string slot unchecked.

Sweep: all 1425 non-`_fail` .py/.npy files under test/, examples/ and apps/
were compiled with the first version of the check. There was one hit, the false
positive above, which the narrowing removed. No program in the tree is refused.

Tests:
- `test/test_nilpy_a_module_name_rebound_to_a_string_in_a_block_is_refused_fail.npy`
  (the refusal fires). Renamed 2026-11-11 to
  `test_nilpy_a_module_name_rebound_across_types_in_a_block.npy`, now a
  CPython-diffed pass test.
- `test/test_nilpy_a_module_name_annotated_any_rebinds_across_types_in_a_block.npy`
  (the named fix works, diffed against CPython).

## What is still open

1. The real fix: the module pre-pass should widen these names itself. One way
   is to trial-parse a block binding's RHS when every identifier in it already
   resolves (a builtin, a def, a class, a module name). Another is to widen to
   a variant any module name with two or more bindings where at least one is
   unreadable; that is correct but makes accumulator loops slower.
2. A number stored into an object or string slot (see above). It needs a
   reliable static kind for operators over objects first.
3. Other binding forms (for targets, tuple unpack, augmented assignment) do not
   go through this check.

## The real fix (2026-11-11)

Open item 1, the first way. `PyBlkRhsAllResolve` (pyparser.inc) says whether a
block binding's right-hand side can be trial-parsed without risking a Halt:
every bare identifier resolves (a non-phantom symbol of this unit, a routine, a
class, or a short builtin list: len, str, int, float, abs, min, max, sorted,
list, dict, tuple, repr, round, sum, bool, ord, chr, hex), and it opens no
scope (no `for`, `def`, `class`, `lambda`, `yield`, `await`, ternary `if`,
colon). Member names after `.` and keyword labels are not looked up. When it
holds, PyCollectModuleLocalsAST trial-parses the statement exactly as the
depth-0 arm does, after the no-parse shapes and before the phantom fallback.
`x = len(a)` then `x = "s" * 3` in one loop now widens x to a variant and
prints `sss`, as CPython does.

PyRefuseUnwidenedModuleRebind stays as the backstop for anything the resolve
check still declines. Items 2 and 3 are unchanged.

Test: `test/test_nilpy_a_module_name_rebound_across_types_in_a_block.npy`
(row blkrebindstr26, now diffed against CPython).
