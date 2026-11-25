---
slug: bug-c-pointer-arithmetic-on-an-element-of-an-array-of-pointers-steps-bytes
track: C
prio: 80
type: bug
status: done
owner: pxx2
created: 2026-11-26
closed: 2026-11-26
found-by: pxx2 (Path B's Xorg in QEMU: st and every other client crashed on the first key press)
tags: [cfront, ir, pointer-arithmetic, arrays, silent-miscompile]
summary: "An element of an array of pointers (`T *a[4]`, a global, or a field `T *f[4]`) did its pointer arithmetic in bytes: `a[i] + 1` stepped one byte and `a[i] - base` gave the byte distance. IRPointerStride had arms for `T **` and for an indexed pointer field, and none for a real array of pointers, so it fell to the 1-byte default. Xorg's xkmread.c stores `type[g] - &xkb->map->types[0]` as each key's type index, which came out 40 times too big; XkbTranslateKeyCode then read a type far outside the table. The new CArrOfPtrElem covers `a[i]`, `*a` and `*(a + i)`. Test c_xgaps26 against gcc."
---

# Pointer arithmetic on an element of an array of pointers steps bytes

```c
XkbKeyTypePtr type[XkbNumKbdGroups];
...
xkb->map->key_sym_map[i].kt_index[g] = type[g] - (&xkb->map->types[0]);
```

The Xorg server loads its keymap through xkmread.c. Under pxx each key's
`kt_index` came out as the type's byte offset (80 for the TWO_LEVEL type,
40 bytes each) instead of 2. The server stored it in a `unsigned char`
and sent it to clients unchanged. libX11's XkbTranslateKeyCode then
indexed `types[80]` of 26, took a garbage `map` pointer, and st segfaulted
on the first key. The keyboard looked fine up to that point: the map
fetch, the device switch and the key events were all correct.

The bisection on the client side went nowhere. Every client libX11 build
crashed, including gcc-built XKB sources, because the bad index came from
the server. Dumping `key_sym_map[kc].kt_index` in QEMU against the host's
Xvfb (80 against 2) pointed at the server.

The parentheses in the Xorg line do not matter. Any element of a real
array of pointers was affected, as a local, a global or a struct field:

| expression | pxx before | gcc |
|---|---|---|
| `type[1] - arr` (`T *type[4]`, 40-byte T) | 200 | 5 |
| `ia[1] + 1 - iv` (`int *ia[4]`) | 25 | 7 |
| `s.f[1] - arr` (`T *f[4]` field) | 160 | 4 |
| `ca[1] - cs` (`char **ca[4]`) | 16 | 2 |
| `*(type + 1) - arr` | 200 | 5 |
| `pp[1] - arr` (`T **pp`) | 5 | 5 |

`a[i][j]` was right, because subscripts take their own path. Only `+`,
`-`, `++` and the difference read IRPointerStride.

The new arm takes the element type from the symbol's (or field's)
PtrElemTk/PtrElemRec. A one-dimensional array of pointers is required. When
the pointee is unknown, the function falls through to the old answer.
