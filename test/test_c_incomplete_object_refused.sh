#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
# An object of a struct/union type with no definition in scope, or sizeof on
# one, is REFUSED (gcc: "storage size of 'v' isn't known" / "invalid
# application of sizeof to incomplete type"). It used to get size 0 silently.
# Every row's expected verdict is gcc's, measured with `gcc -c`.
# Legal rows must still compile: a pointer to an incomplete type, extern,
# a tentative file-scope definition completed LATER in the file, and the GNU
# empty struct (size 0, not refused).
# bug-c-an-undeclared-struct-type-compiles-and-reads-garbage
# Usage: test/test_c_incomplete_object_refused.sh <compiler>   (exit 0 = pass)
PXX=${1:-./compiler/pascal26}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0
row() {   # row <name> <want: refuse|accept> <source>
  printf '%s\n' "$3" > "$T/$1.c"
  "$PXX" "$T/$1.c" "$T/$1.out" > "$T/$1.log" 2>&1; rc=$?
  if [ "$2" = refuse ]; then
    if [ $rc -ne 0 ] && grep -q "isn't known\|INCOMPLETE" "$T/$1.log"; then echo "PASS $1 refused"
    else echo "FAIL $1: want refused, rc=$rc"; head -3 "$T/$1.log"; fail=1; fi
  else
    if [ $rc -eq 0 ]; then echo "PASS $1 accepted"
    else echo "FAIL $1: want accepted, rc=$rc"; head -3 "$T/$1.log"; fail=1; fi
  fi
}
row local        refuse 'int main(void){ struct nosuch v; return 0; }'
row local_array  refuse 'int main(void){ struct nosuch v[3]; return 0; }'
row local_static refuse 'int main(void){ static struct nosuch v; return 0; }'
row typedef_obj  refuse 'int main(void){ typedef struct nosuch NT; NT v; return 0; }'
row sizeof_type  refuse 'int main(void){ return (int)sizeof(struct nosuch); }'
row block_fwd    refuse 'struct T { int a; }; int main(void){ { struct T; struct T x; return 0; } }'
row global       refuse 'struct nosuch gv; int main(void){ return 0; }'
row global_2nd   refuse 'struct nosuch *b, a; int main(void){ return 0; }'
row global_stat  refuse 'static struct nosuch sv; int main(void){ return 0; }'
row pointer      accept 'struct op; int main(void){ struct op *p = 0; return p != 0; }'
row ptr_sizeof   accept 'int main(void){ struct nosuch *p = 0; return (int)sizeof(p) == 0; }'
row extern_blk   accept 'int main(void){ extern struct ex xv; return 0; }'
row extern_file  accept 'extern struct nosuch ev; int main(void){ return 0; }'
row tentative    accept 'struct T gv; struct T { int a, b; }; int main(void){ gv.b = 7; return gv.b - 7; }'
row empty_gnu    accept 'int main(void){ struct E { }; struct E e; return (int)sizeof(struct E) + (int)sizeof e; }'
row ptrs_only    accept 'struct nosuch *b, *c; int main(void){ return b != c; }'
[ $fail -eq 0 ] && echo "OK test_c_incomplete_object_refused" || echo "FAIL test_c_incomplete_object_refused"
exit $fail
