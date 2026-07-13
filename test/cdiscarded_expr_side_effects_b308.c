/* An expression statement whose VALUE is discarded must still be EVALUATED.

   The IR is emitted by walking from its roots, so a node nothing references is an
   orphan and never gets emitted. IRMarkStatementNode marked the CALL kinds, which
   covered a bare `f();` -- but not an expression whose ROOT is something else and
   which merely CONTAINS a call. Those roots were dropped, and the call went with
   them, so the side effects silently never happened:

       f() ^ 3;              -- f() never called
       (void)(f() + 1);      -- f() never called
       x = ((f() ^ K), 0);   -- f() never called; this is how csmith found it

   Now any non-call root is forced into a hidden temp: a store IS a statement root, so
   it is emitted and drags its whole operand tree, calls included, in the right order.

   Every line here is a side-effect COUNT, not a value -- the values were always right,
   which is exactly why this stayed invisible. */
int printf(const char *, ...);

static int side = 0;
static int bump(void) { side++; return 7; }
static int idn(int x) { return x; }

int main(void)
{
    int x;
    unsigned short g = 0x64BA;

    side = 0; bump();                    printf("bare-call=%d\n", side);
    side = 0; bump() ^ 3;                printf("binop=%d\n", side);
    side = 0; (void)(bump() + 1);        printf("cast=%d\n", side);
    side = 0; 1 ? bump() : 0;            printf("ternary=%d\n", side);
    side = 0; idn(bump()) + idn(bump()); printf("two-calls=%d\n", side);
    side = 0; -bump();                   printf("unary=%d\n", side);

    /* comma: the left operand is evaluated for effect, the value is the right one */
    side = 0; g = ((bump() ^ 0x5A5A), 0); printf("comma-assign=%d g=%u\n", side, (unsigned)g);
    side = 0; x = (bump(), bump(), 9);    printf("comma-chain=%d x=%d\n", side, x);
    side = 0; if ((g = ((bump() ^ 3), 0))) printf("BAD\n");
              else printf("comma-in-if=%d\n", side);
    return 0;
}
