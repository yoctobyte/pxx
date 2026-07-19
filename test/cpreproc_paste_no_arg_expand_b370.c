int printf(const char *fmt, ...);
#define true 1
#define MK(name) int val_ ## name
MK(true) = 7;
#define STR2(x) #x
#define STR(x) STR2(x)
#define S(name) #name
int main(void) {
    printf("%d %s\n", val_true, S(true));
    if (val_true == 7) return 42;
    return 1;
}
