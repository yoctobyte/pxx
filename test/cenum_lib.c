enum Color { RED, GREEN, BLUE };

typedef enum {
    F_NONE = 0,
    F_A = (1 << 0),
    F_B = (1 << 1),
    F_C = (1 << 2),
    F_AC = F_A | F_C
} Flags;

enum { BIG = 1000, BIGGER };

int dummy(int x);
int dummy(int x) { return x; }
