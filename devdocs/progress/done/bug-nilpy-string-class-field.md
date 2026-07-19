---
track: N
prio: 60
type: bug
---

# NilPy: str class field registered as tyString = inline string[N] semantics (garbage reads)

Pre-existing: NilPy registered `str` class fields as tyString with an 8-byte
slot, but the shared AN_ASSIGN store path treats a tyString FIELD as an
inline `string[N]` shortstring (capacity-clamped CONTENT copy via
RecFieldStrCap). Result: correct length, garbage bytes — `self.a = a` then
`print(obj.a)` printed spaces. Both __init__ and dataclass paths affected.

Fix: NilPy str fields register as tyAnsiString (pointer semantics, managed);
the existing tyString->tyAnsiString conversions cover ctor args and stores.
