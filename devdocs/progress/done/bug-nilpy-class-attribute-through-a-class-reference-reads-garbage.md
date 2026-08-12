---
track: N
prio: 60
type: bug
blocked-by: []
summary: "`c = A` then `c.num` answers 24 where CPython answers 7 and `c.name` answers the empty string: a class attribute read through any class REFERENCE (alias, parameter, dict or list element) is garbage, while the literal `A.num` is correct. The WRITE side is lost too — `c.num = 9` leaves A.num at 7. The plugin-registry shape: register(cls), then registry[k].name"
status: done
owner: claude-AN
---

# A class attribute read through a class REFERENCE reads garbage

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-12, differential bug hunting against CPython — a plugin
  registry (`register(cls)` keyed on `cls.name`), which is the canonical use of
  a class as a value.
- **Sibling:** [[bug-nilpy-class-attribute-unreachable-through-the-class-name]]
  (done) made the LITERAL `A.attr` work. This is the same read one step of
  indirection later, and it is silent where that one was loud.

```python
class A:
    name = "a"
    num = 7

def f(cls):
    return cls.name

c = A
d = {"k": A}
lst = [A]
```

| read | pxx | CPython |
| --- | --- | --- |
| `A.name` / `A.num` (the literal class) | `'a'` / `7` | same |
| `c.name` / `c.num` (an ALIAS) | **`''`** / **`24`** | `'a'` / `7` |
| `f(A)` — through a parameter | **`''`** | `'a'` |
| `d["k"].name` | **`''`** | `'a'` |
| `lst[0].name` | **`''`** | `'a'` |
| `A().name` (through an INSTANCE) | `'a'` | `'a'` |

`c.num` answering **24** is the one that matters: a plausible integer, no
error, no warning. The string reads answer empty, which is the same failure
mode one type over. The instance read and the literal read are both fine, so
the attribute exists and is stored correctly — it is reading it off a class
HANDLE that goes wrong.

In a full registry program the failure surfaces earlier and louder:
`AttributeError: 'type' object has no attribute 'name'` when the class comes
back out of a dict, which is what a plugin/handler table does on every lookup.

## Where to look

A class held as a value is a `VT_CLASSREF` variant
([[project_nilpy_callable_has_three_representations]] is the same family of
hazard: several representations for one concept, and crossing them writes one
kind's payload into another kind's slot). The literal `A.attr` is resolved by
the frontend against the class's own attribute table; the reference form has
to go through the RTTI the class-as-a-value work already reflects for
construction (`PyClassRefNew`). Expect the attribute read to be falling through
to an INSTANCE field read on a handle that is a class-ref, i.e. reading at the
field's offset inside the RTTI blob — which is exactly the shape of a 24 where
7 was stored.

**The write side is wrong too, and measured:**

```python
class A:
    num = 7
c = A
c.num = 9
print(A.num, c.num)     # pxx: 7 9      CPython: 9 9
print(A().num)          # pxx: 7        CPython: 9
```

So `c.num = 9` does NOT write the class attribute — it lands somewhere the
alias reads back and the class does not, which is why the read through the alias
then looks self-consistent. A registry that sets a default on a registered
class (`cls.enabled = False`) therefore silently changes nothing that any
instance or the class itself will see. Whatever slot it does write has to be
identified as part of this: if it is inside the RTTI blob, that is memory
corruption, not just a lost write.

`getattr(cls, "name")` is worth a row too — it is the other spelling of the
same read.

## 2026-08-12 — read the model before starting; this is not a small fix

A class attribute is NOT stored on the class. `PyClsAttrSlot` (pyparser.inc
~4220) gives each one a hidden GLOBAL named after `(ci, name)` and registers it
as a CLASS VAR of `ci`, and all three working access routes are compile-time
lookups of that slot:

  * `C.attr` — parser.inc's `ClassName.member` branch, via `FindClassVar`
  * bare `attr` inside a method body
  * `inst.attr` — the class-variable-through-an-instance branch

Every one of those needs to know the CLASS at compile time. A class held as a
value is a `VT_CLASSREF` variant, so `c.name` has no class index at the point
of the read and falls through to the dynamic instance-attribute path, which
reads at a field offset inside the RTTI blob — hence a 24 where 7 was stored,
and an empty string for a str.

So the runtime has nothing to consult: the attribute's value lives in a global
whose name only the frontend knows, and the RTTI blob (which the class-as-a-
value work already reflects for `create`) carries methods, not attributes.
Fixing this properly means giving the RTTI blob a class-ATTRIBUTE table — name,
kind, and the address of that hidden global — and routing the variant-receiver
read and write through it, the same way `PyClassRefNew` reflects the
constructor. That is the ticket, and it is a feature-sized one.

**A cheaper partial exists and should be a deliberate choice, not a default:**
the ALIAS row (`c = A`) could be typed at compile time — the pre-pass sees a
bare-ident assignment from a known class name and could record `c` as a
class-ref to that class, after which `c.attr` resolves exactly like `A.attr`.
That fixes the row that is currently silent garbage and leaves the parameter /
dict / list rows still wrong, which argues for doing the RTTI table instead.

## Gate

A `.npy` diffed against CPython: every row of the table above for a str, an
int and a float attribute; a class reference passed through two calls; a
registry dict keyed by `cls.name` (the shape that found this); an inherited
class attribute read through a reference to the SUBCLASS; the write side; and
`A.attr` / `A().attr` kept in the same file as the controls.

## 2026-08-12 — FIXED, and not by the cheap partial

Done as the ticket asked: the run time can now be *told* where a class
attribute lives, instead of the alias row being special-cased.

**The link that was missing.** A class attribute's value is in a hidden GLOBAL
named `$clsattr.<Class>.<attr>`; the RTTI blob carries methods and instance
fields and could never name it. So the frontend now PUBLISHES it: `PyParseClass`
emits one `pyclsattr_bind(<RTTI blob>, "attr", @slot, kind)` per class attribute,
hoisted where the class statement runs (`PyEmitClsAttrBinds`, pyparser.inc). The
bind carries the slot ADDRESS, so a reference reaches the very memory the three
compile-time routes reach — the read and the write cannot drift apart.

Deliberately a runtime registry keyed on the blob pointer, NOT a new table
inside the blob: a blob-resident table would need a data→BSS fixup kind that
does not exist, in every ELF writer for every target. The registry is filled at
class-definition time and walks `ParentRTTI`, so an inherited attribute is found
through a reference to the subclass.

**The five routes now agree:** `pydynattr_get_v` / the new `pydynattr_set_v` /
the new `pydynattr_has_v` check tag 11 FIRST (the old code unwrapped the payload
as an instance pointer and read at a field offset INSIDE the blob — the 24), and
`PyHasAttr` answers for a class object. A miss raises CPython's wording,
`type object 'A' has no attribute 'x'`.

**The write side needed a lowering change too.** Writing the shared slot is only
the whole answer if instances read that slot, so a class whose kin is used as a
VALUE now takes the shared-slot lowering rather than copy-at-construction
(`PyClassKinUsedAsValueEx(ci, precise)`).

`precise` is the load-bearing word, and both halves of it were found by a RED
suite, not by reading:

  * the existing scan does not skip `A.attr`, so `print(Plain.n)` demoted every
    class anyone reads an attribute off — `p1.bag.append(1)` then died with
    "object is not callable";
  * the existing scan matches case-INSENSITIVELY, so `k = K()` counted the
    receiver `k` as a value use of `K`, and `hasattr(k, "pass2")` went False.
    Same family as
    [[bug-nilpy-a-lowercase-name-is-hijacked-by-a-case-matching-class]].

The coarse form is unchanged and still what constructor widening uses, where a
false positive costs only boxing.

**Found while doing it, filed, not worked around:**
[[bug-p-a-typecast-of-a-variant-reinterprets-it-instead-of-converting]] —
`Int64(v)` on a Variant answers the tag word `1` where FPC answers 9, and
`Double(v)` segfaults. It is what made the first cut store 1 into `c.num = 9`
and read stack addresses out of the registry. The runtime code here assigns
through a typed local instead; the cast bug is a Track P ticket of its own.

**Residual, deliberate:** an instance built BEFORE a class-attribute write still
answers the old value if the class is never used as a value elsewhere — that is
the pre-existing copy-at-construction model
([[decide-nilpy-class-attribute-instance-read-model]]), untouched here.

Gate: `test/test_nilpy_class_attribute_through_a_class_reference.npy` (+
`.expected` from CPython, wired into `make test-nilpy`) — every row of the table
above for str/int/float/bool, inheritance, two calls deep, getattr/hasattr, the
registry shape, the write side, and the AttributeError. `make test-nilpy` green.

## Log
- 2026-08-12 — resolved, commit 069a3b740.
