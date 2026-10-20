---
track: N
prio: 20
type: bug
---

# A nested unpack target with attribute leaves did not parse

Vloot: `(self.enc, self.enc_value), (self.dec, self.dec_value) = pair(...)`
failed with "expected expression" (the pin still does).

**Fix:** the nested-unpack records (PyNestAdd / PyParseNestGroupInto /
PyNestEmit) take an `ident.ident` leaf in an assignment group. It is held
under a hidden name and stored through PyMakeAttrStore. PySkipTargetGroup
steps over it the same way.

Test: test_nilpy_nested_unpack_into_attributes.
