---
slug: bug-c-a-block-scope-static-did-not-shadow-a-typedef
track: C
prio: 75
type: bug
status: done
created: 2026-11-16
found-by: found writing c_dcls: any program with `typedef ... X;` failed inside crtl stdio.c (present on ~/pxx-frozen/latest)
tags: [cfront, scoping, crtl]
blocked-by: []
summary: "A user `typedef struct {..} X;` broke every program using printf: crtl's stdio.c has a block-scope `static struct __crtl_dexp X;`, block-scope statics are skGlobal, and CTypedefShadowed only accepted skLocal/skParam, so `X.df[i] = 0;` parsed as a declaration (\"expected C expression\" in stdio.c). Block-scope statics are now noted with their function (CNoteBlockStatics) and shadow a typedef inside that function. Test: c_dcls (its typedef X)."
---
