# C: global `double`/`float` initializer stored as 0

- **Type:** bug (C frontend — Track C / data emission)
- **Status:** backlog
- **Found / Opened:** 2026-06-27 (Track A+C, surfaced while isolating the
  C double-value-model fixes — a `static double srcv = 3.14;` test scaffold
  read back 0, a false lead that cost time to rule out)

## Symptom

A file-scope (`static`/global) floating-point variable with an initializer is
emitted as **all-zero** in the data section; the initializer value is dropped.
Integer globals initialize correctly.

```c
static double g = 3.14;
int main(void) { long b = *(long*)&g; return (b >> 56) & 0xff; }   /* -> 0, want 0x40 */

static int i = 42;
int main(void) { return i; }                                       /* -> 42 OK */
```

Live-verified 2026-06-27 on HEAD (after the double-value-model fixes): the
double global reads 0, the int global reads 42.

## Likely root area

C global/static initializer emission (`cparser.inc` global-var path +
PendingInit/data-section writeback). The float initializer is either not
const-folded into its IEEE bit pattern at data-emit time, or written at the
wrong width (4 bytes / int) so the 8-byte double slot stays zero. Sibling of the
`static double[]` array-init gap noted in
[bug-c-float-int-cast-and-spill] (now done) and the global-array-init remark in
the C stdio bring-up notes.

## Impact

Low for lua (its constants live in the bytecode `k` table, not C globals), which
is why the interpreter runs floats correctly. Bites any hand-written C that keeps
float constants/tables at file scope (math lookup tables, config). A `cglobal_*`
regression test (returns 42) should pin it once fixed.

## Fix direction

In the C global-init path, const-fold a float initializer to its 64-bit (Double)
/ 32-bit (Single) IEEE pattern and emit it at the variable's full width into the
data section, matching the integer-global path. Front-end / data-emit only ->
self-host byte-identical.
