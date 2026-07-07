/* b187: ptrdiff stride of a DEREF'd pointer-to-pointer — `++*(p)` where p is
   an int** must step sizeof(int), and `*(&mp)` is mp itself (same stride).
   Missing AN_DEREF/AN_ADDR cases fell to the size-1 default and stepped
   BYTES: tcc's TOK_GET macro walks its token stream through an int** (and,
   via macro substitution, through `*(&macro_ptr)`) — tokens read misaligned,
   killing every function-macro expansion. */
int main(void)
{
    int arr[4];
    const int *mp;
    const int **p;
    int t;

    arr[0] = 10; arr[1] = 20; arr[2] = 30; arr[3] = 0;
    mp = arr;
    p = &mp;

    t = **p;                    /* 10 */
    ++*(p);                     /* one INT forward */
    if (t != 10 || **p != 20) return 1;
    ++*p;
    if (**p != 30) return 2;

    mp = arr;
    t = **(&mp);                /* 10 */
    ++*(&mp);                   /* one INT forward */
    if (t != 10) return 3;
    if ((int)(mp - arr) != 1) return 4;
    if (**(&mp) != 20) return 5;

    return 42;
}
