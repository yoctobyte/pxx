---
title: "C: a const-qualified nested struct member was dropped"
status: done
owner: claude-dupwt
prio: 75
area: cfront
---

`struct nvif_parent { const struct nvif_parent_func { ... } *func; };` has a
nested struct body behind a `const`. ParseCStructInto checks for a nested
aggregate body only when the member starts with `struct` or `union`, so the
qualifier sent it down the plain-member path. That path lost the member:
"no member named 'func'". In the fifth GPU-driver census
(feature-nodisx-linux-gpu-drivers-built-by-pxx) this was 97 compiles for
`func`, 249 for the `rm` member in nouveau's gsp.h, and 13 for `funcs`, all
one shape.

Fix: const and volatile in front of a nested aggregate body are stepped over
(CNestedAggAfterQuals). Test row c_qnest26.
