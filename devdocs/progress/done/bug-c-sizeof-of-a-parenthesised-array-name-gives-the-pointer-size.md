---
slug: bug-c-sizeof-of-a-parenthesised-array-name-gives-the-pointer-size
track: C
prio: 70
type: bug
status: done
owner: pxx2
created: 2026-11-25
closed: 2026-11-25
found-by: pxx2 (Path B's Xorg in QEMU: the output was "Unknown15-1", not "Virtual-1")
tags: [cfront, sizeof, arrays, silent-miscompile]
summary: "`sizeof((arr))` -- the operand array name in a redundant pair of parentheses -- gave the size of a pointer, not of the array, with no diagnostic. ARRAY_SIZE written as `sizeof((a)) / sizeof((a)[0])`, as Xorg's modesetting writes it, answered 1, so drmmode_display.c named every output past connector type 0 \"Unknown<type>\". `sizeof(arr)` and `sizeof((arr)[0])` were right. ParseCSizeof now removes any pair that wraps the whole operand before looking at it, however deeply nested. Test c_xgaps26 against gcc."
---

# sizeof of a parenthesised array name gives the pointer size

```c
#define ARRAY_SIZE(a) (sizeof((a)) / sizeof((a)[0]))
static const char *const output_names[] = { "None", ..., "Virtual", "DSI", "DPI", };

if (koutput->connector_type >= ARRAY_SIZE(output_names))
    snprintf(name, 32, "Unknown%d-%d", ...);
```

pxx gave `sizeof((output_names))` as 8, the size of the decayed pointer,
instead of 144. The general-expression path sized the operand by its
result type, and a parenthesised name had already decayed to a pointer
there.

A pair counts as wrapping the whole operand only when its closing `)` is
immediately followed by sizeof's own `)`. `((a)[0])`, `((T)x)` and
`((T){...})` are left alone.

The first fix (21efc589d2) removed the redundant pair from the token stream.
That moved every later token position, and a static initialiser records
its positions before this point, so `sizeof(XtRString)` in xload's resource
table (a macro that expands to `((char*)&XtStrings[n])`) broke the parse:
"expected C expression", in 19 Path B units. The quick gate passed. The fix
now steps over the wrapping pairs and expects their `)`s after the operand,
leaving the tokens alone.
