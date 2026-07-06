/* Regression: sizeof of a general expression NOT starting with an identifier
   sizes by result type — C `!` yields int (4) regardless of operand width.
   Returns 42. (Ident-starting exprs like sizeof(a<b) need the wider integer
   type model — see bug-c-expr-result-type-model.) */
int main(void) {
    char a = 1;
    int  b = 2;
    if (sizeof(!a) != 4) return 1;         /* !char -> int */
    if (sizeof(!b) != 4) return 2;         /* !int  -> int */
    if (sizeof(!(a + 0)) != 4) return 3;   /* paren, non-ident start */
    return 42;
}
