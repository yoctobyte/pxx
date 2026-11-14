---
track: C
tags: [C, diagnostics, sizeof]
prio: 60
type: bug
blocked-by: []
summary: "`sizeof(x.zz)` compiles and evaluates to 4 when the struct or union has no member zz. gcc refuses it. Reading or assigning `x.zz` is refused correctly ('no member named'); only the sizeof operand skips the member lookup."
status: open
owner: unassigned
---

# An unknown member name under sizeof compiles as int

Seen while diagnosing [[bug-c-array-plus-int-derefs-as-int-so-a-byte-store-writes-four]]:
a probe printing `sizeof(h.md5)` on libtomcrypt's `hash_state` (which has no
md5 member in dropbear's configuration) printed 4 under pxx. gcc stops with
"has no member named 'md5'".

```c
struct s { int a; char c; };
union u { struct s s; long l; };
int main(void) { struct s x; union u y;
  printf("%d %d\n", (int)sizeof(x.zz), (int)sizeof(y.md5)); }   /* pxx: 4 4 */
```

`x.zz = 5` and reading `x.zz` both give "C: no member named 'zz' in this
struct/union". So the sizeof path types the operand without going through
the member check.

Harm: a wrong size is silent where a configuration difference removes a
member, as here. Fix it by making sizeof's operand typing reach the same
lookup and refusing it. A regression test should cover the struct and the
union cases (a refusal row).
