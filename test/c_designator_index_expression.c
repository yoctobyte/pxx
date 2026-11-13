/* `[expr] =` array designators whose index is an expression, not a literal
   or a lone enum name: busybox od's integral_type_size table is
   `{ [sizeof(char)] = CHAR, [sizeof(short)] = SHORT, ... }`. The flat-init
   pre-scan understood only `[3]` and `[NAME]` and bailed on anything else, and
   the path it fell to kept none of the values, so the table read all 0
   (`od -to2`: "2-byte integral type is not supported"). Built by pxx and by
   gcc; the outputs must match.
   bug-c-a-designator-index-expression-drops-every-value-of-a-sized-array */
#include <stdio.h>
enum { NO_SIZE, CHAR, SHORT, INT, LONG };
#define K 2
static const unsigned char its[sizeof(long long) + 1] = {
    [sizeof(char)] = CHAR, [sizeof(short)] = SHORT,
    [sizeof(int)] = INT, [sizeof(long)] = LONG,
};
static int g[6] = { [K + 1] = 30, 40, [K * 0] = 7 };
static unsigned char u[] = { [sizeof(int)] = 9 };
int main(void)
{
    static const short ls[5] = { [sizeof(short)] = 22, [(1 << 2)] = 44 };
    int la[5] = { [sizeof(char) + 1] = 5, [K + 2] = 6 };
    for (int i = 0; i < 9; i++) printf("%d ", its[i]);
    for (int i = 0; i < 6; i++) printf("%d ", g[i]);
    printf("| %d %d |", (int)sizeof u, u[4]);
    for (int i = 0; i < 5; i++) printf(" %d %d", ls[i], la[i]);
    printf("\n");
    return 0;
}
