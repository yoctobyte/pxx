typedef enum { KA = 1, KB = 2 } Kind;
int printf(const char *fmt, ...);
static Kind get(int x) {
    if (x) return KA;
    return (Kind){-1};
}
int main(void) {
    int a = (int){40};
    Kind k = get(0);
    printf("%d %d\n", a, (int)k);
    if (a == 40 && (int)k == -1) return 42;
    return 1;
}
