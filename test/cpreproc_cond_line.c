/* Three #if-evaluator gaps that were invisible until `#error` started firing.
   A wrong `#if` never announces itself — it silently takes the other branch —
   so all three sat in the c-testsuite passing "green" because the `#error` that
   was supposed to catch them was itself a no-op (00075, 00145, 00152).

     1. `?:` had no precedence level at all: the parse abandoned at the `?`, so
        the condition's own value became the whole expression's. `(1 ? 3 : 1)`
        compared equal to EVERY right-hand side and `(0 ? 1 : 3)` to none.
     2. `#line N` was not implemented, so it could not renumber what __LINE__
        and later diagnostics report.
     3. `__LINE__` is synthesised during macro expansion, a path the #if
        evaluator never takes — inside `#if` it read as an undefined identifier,
        i.e. 0.

   bug-cfront-if-ternary-unimplemented / bug-cfront-line-directive-unimplemented */

/* --- 1. ternary in #if --- */
#if (0 ? 1 : 3) != 3
#error ternary with a false condition took the wrong arm
#endif
#if (1 ? 3 : 1) != 3
#error ternary with a true condition took the wrong arm
#endif
#if (-1 ? 3 : 99) != 3
#error nonzero (not just 1) must count as true
#endif

/* the untaken arm must not blow up — this is what the c-testsuite guards with,
   and it is why `&&` / `||` / `?:` all have to tolerate 0/0 here */
#if (-1 ? 3 : (0/0)) != 3
#error untaken else-arm was evaluated
#endif
#if (0 ? (0/0) : 7) != 7
#error untaken then-arm was evaluated
#endif

/* right-associative: a ? b : c ? d : e  ==  a ? b : (c ? d : e) */
#if (1 ? 2 : 0 ? 4 : 8) != 2
#error nested ternary: first arm
#endif
#if (0 ? 2 : 1 ? 4 : 8) != 4
#error nested ternary: middle arm
#endif
#if (0 ? 2 : 0 ? 4 : 8) != 8
#error nested ternary: last arm
#endif

/* ternary composes with the rest of the grammar */
#if (1 ? 2 : 3) + (0 ? 10 : 20) != 22
#error ternary as an operand of +
#endif
#if !(1 ? 1 : 0)
#error ternary under unary !
#endif

/* --- 2 + 3. __LINE__ inside #if, and #line renumbering it --- */
#if __LINE__ == 0
#error __LINE__ evaluated as an undefined identifier inside #if
#endif

#line 1000
#if __LINE__ != 1000
#error #line did not renumber the following line
#endif

/* a macro may supply the operand: `#define line 1000` / `#line line` */
#define RENUM 2000
#line RENUM
#if __LINE__ != 2000
#error #line did not macro-expand its operand
#endif

/* renumbering keeps counting from there */
#if __LINE__ != 2005
#error #line renumbering did not continue on later lines
#endif

#line 90
int main(void) {
    return 42;
}
