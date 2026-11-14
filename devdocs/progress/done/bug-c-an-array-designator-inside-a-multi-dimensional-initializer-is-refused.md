---
track: C
prio: 25
type: bug
status: done
found: 2026-09-27
found-by: frankD
owner:
summary: "An index designator inside a multi-dimensional local initializer, `int e[4][3] = {{1}, [3] = {9}};`, is refused with \"expected C expression\". gcc accepts it (e[3][0] = 9). The multi-dim brace pre-scan in the local declaration path has no designator arm; the 1-D arm has one. Loud, not wrong. Same on the v441 pin."
---

# An array designator inside a multi-dimensional initializer is refused

```c
int e[4][3] = {{1}, [3] = {9}};   /* pxx: error: expected C expression */
printf("%d %d\n", e[0][0], e[3][0]);  /* gcc 1 9 */
```

Found 2026-09-27 while varying the unsized-outer-dimension fix in
bug-c-an-array-of-pointers-to-arrays-has-no-pointee-shape-so-deref-loads-instead-of-decaying.
The walk is the `beFlat` brace pre-scan in the local path; a designator at
depth `d` sets the flat cursor to `index * (product of the dims below d)`.
File-scope arrays have not been measured.

## Resolved 2026-11-14

Fixed: the local multi-dim brace pre-scan has a designator arm. `[i]` at brace
depth d moves the flat cursor to the start of the sub-aggregate that brace
opened plus i times one element of dimension d-1; a chain `[i][j]` continues
into the next dimension. An index past a sized dimension is refused. A
braced value after a CHAINED designator (`[i][j] = {...}`) is refused by
name; `[i] = {[j] = {...}}` is the supported spelling.

Test: test/c_declarator_and_sizeof_shapes.c (`{{1}, [3] = {9}}`,
`{[1][1] = 5, [0] = {1, 2}}`, a 3-D nest, an unsized outer dimension).
File scope already worked (`static int g[2][2] = {[1] = {3, 4}}`).
