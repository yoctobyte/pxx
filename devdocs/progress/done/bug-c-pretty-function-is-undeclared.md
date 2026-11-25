---
slug: bug-c-pretty-function-is-undeclared
track: C
prio: 50
type: bug
status: done
owner: pxx2
created: 2026-11-25
closed: 2026-11-25
found-by: pxx2 (pixman for Path B Xorg)
tags: [cfront, gnu-extensions]
summary: "`__PRETTY_FUNCTION__` and `__FUNCTION__` were undeclared identifiers; only `__func__` was known. pixman's FUNC macro uses `__PRETTY_FUNCTION__`. All three now name the enclosing function's name as a string (in C, gcc gives the plain name for all three). Test c_xgaps26."
---

# __PRETTY_FUNCTION__ is undeclared

gcc's C front end makes `__FUNCTION__` and `__PRETTY_FUNCTION__` the same
string as `__func__` (the C++ pretty form does not apply). The `__func__`
branch in cparser accepts all three names.
