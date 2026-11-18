/* A bitfield whose type is a TYPEDEF'd enum: gcc makes it unsigned when no
   enumerator is negative, so `side_t side : 2` holding 2 reads back 2. pxx
   read -2 (LVGL's line masks: every triangle came out transparent).
   bug-c-a-typedef-enum-bitfield-reads-back-sign-extended */
#include <stdio.h>

typedef enum { S_LEFT = 0, S_RIGHT, S_TOP, S_BOTTOM } side_t;
typedef enum { N_NEG = -1, N_ZERO, N_ONE } sgn_t;   /* has a negative: stays signed */
typedef enum tagged { T_A = 5, T_B, T_C } tagged_t;
typedef side_t side_alias_t;                          /* an alias keeps it */
enum plain { P_A, P_B, P_C, P_D };

struct cfg {
    int a;
    side_t side : 2;
    sgn_t s : 2;
    tagged_t t : 3;
    enum plain p : 2;
    unsigned u : 2;
    int i : 2;
    side_t full : 8;
    side_alias_t al : 2;
};

int main(void) {
    struct cfg c = {0};
    int k;
    for (k = 0; k < 4; k++) {
        c.side = (side_t)k;
        printf("side %d eq %d gt1 %d\n", (int)c.side, c.side == (side_t)k, c.side > S_RIGHT);
    }
    c.s = N_NEG;  printf("signed enum %d\n", (int)c.s);
    c.t = T_C;    printf("tagged %d eq %d\n", (int)c.t, c.t == T_C);
    c.p = P_D;    printf("plain enum %d\n", (int)c.p);
    c.u = 3; c.i = 3;
    printf("unsigned %d int %d\n", (int)c.u, (int)c.i);
    c.al = S_BOTTOM; printf("alias %d\n", (int)c.al);
    c.full = S_BOTTOM; printf("full %d\n", (int)c.full);
    c.side = S_TOP;
    switch (c.side) {
    case S_TOP: printf("switch top\n"); break;
    default: printf("switch other %d\n", (int)c.side);
    }
    return 0;
}
