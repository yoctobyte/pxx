---
track: C
tags: [C, diagnostics, sizeof]
prio: 60
type: bug
blocked-by: []
summary: "`sizeof(x.zz)` compiles and evaluates to 4 when the struct or union has no member zz. gcc refuses it. Reading or assigning `x.zz` is refused correctly ('no member named'); only the sizeof operand skips the member lookup."
status: done
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

## Resolved 2026-11-14

Fixed: the sizeof operand walkers (CSizeofDescriptorWalk, the `sizeof(*s.f)`
arm, the `(expr)->f` arm) sized a member without the existence check the
member-access parse makes. That check is now one routine, CRecMemberCheck
(cparser.inc), called from all of them and from the access parse; it reports
each bad member once even when a walker rewinds over the same tokens.
CSizeofRecFieldBytes no longer sizes a member that does not exist.

Test: test/c_sizeof_unknown_member_refused.c, five spellings (`sizeof(x.zz)`,
`sizeof x.yy`, `sizeof(px->ww)`, `sizeof (*px->vv)`,
`sizeof ((struct s *)0)->uu`), five refusals (row c_sizeof_unknown_member_refused).
