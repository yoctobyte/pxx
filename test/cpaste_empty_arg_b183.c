/* b183: ## paste with an EMPTY argument (C99 placemarker, 00202). The empty
   operand vanishes, and the body token AFTER it must stay a SEPARATE token:
   `A ## B+` with B empty is `+ +`, never `++`. A paste CHAIN with an empty
   middle operand must still glue its outer operands. */

#define P(A,B) A ## B ; bob
#define Q(A,B) A ## B+
#define CHAIN(A,B,C) A ## B ## C
#define xz 7

int main(void)
{
    int bob, jim = 21;
    bob = P(jim,) *= 2;          /* bob = jim; bob *= 2  -> 42 */
    jim = 60 Q(+,)3;             /* 60 + +3 -> 63, NOT 60 ++ 3 */
    if (bob != 42) return 1;
    if (jim != 63) return 2;
    if (CHAIN(x,,z) != 7) return 3;  /* empty middle: x##<>##z -> xz */
    return 42;
}
