int printf(const char *fmt, ...);
#define STEP(n) do { printf("step %s\n", n); } while (0)
int main(void) {
    STEP("a");
    return 42;
}
