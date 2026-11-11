---
track: N
prio: 70
type: bug
status: done
summary: "`super().size() + 10` inside an override of a method of a class from an IMPORTED module segfaulted (any module, flat or package). The override's result was inferred as a variant, and the override join widened the BASE method's result to variant -- but the base module was already compiled and returned an Int64, which the caller dereferenced as a variant pointer. Fixed: a compiled base keeps its type; an inferred-variant override adopts it; a real scalar disagreement is refused by name."
---

# `super()` from an override of an imported class segfaults

Found 2026-11-11 while testing
[[bug-n-a-from-import-alias-resolves-its-source-through-flat-scope]].

```python
# basemod.py
class Trie:
    def size(self):
        return 1

# main.py
from basemod import Trie
class T2(Trie):
    def size(self):
        return super().size() + 10
print(T2().size())      # CPython 11; pxx: Segmentation fault
```

Reproduced on latest-7020208c34 and earlier. `super().size()` from a method of
a DIFFERENT name worked, and so did a base declared in the same file. Only an
override of an imported base's method crashed.

## Mechanism

gdb: the crash was `cmpq $0x3,(%rdi)` with rdi = 1, so a variant-tag test ran
on the integer the base returned. PyRegisterClassMembers joins an override's
result type with its base's, and widens BOTH to a variant when they disagree.
The guard allowed that only "while the base's body is not yet compiled, which
is the pre-pass" (PyInHeaderSweep). A base in an imported module, though, was
compiled before the main program's pre-pass began. The override's result was
only INFERRED as a variant (`super().size() + 10` is untyped at that point), so
the join widened a compiled `Trie.size` that returns an Int64.

## Fix (pyparser.inc, PyRegisterClassMembers)

When the base's body is already compiled (`Procs[ovPi].BodyAddr >= 0`):
- an override whose result is an inferred variant adopts the base's type;
- any other disagreement takes the existing refusal ("overrides ... with a
  different result type, in a class laid out after its base was compiled"),
  whose text now names the imported-module case. Before, `return 1.5` over an
  imported `return 1` also segfaulted.

Test: test_nilpy_super_from_an_override_of_an_imported_class (row
superimp26), which also covers `from m import Trie` then `class Trie(Trie):`
(previously "class Trie cannot inherit from itself"; fixed in the same batch by
PyImportedClassNamed at the three base-assignment sites).
