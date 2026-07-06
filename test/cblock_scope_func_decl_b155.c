/* Regression: block-scope function prototype `int f(params);` is a no-op
   declaration (the function is defined at file scope). Pre-fix pxx tried to
   parse it as a variable and tripped on '('. Returns 42. */
int add1(int x) { return x + 1; }
int main(void) {
    int v[8];
    int add1(int);          /* block-scope prototype, no code */
    v[0] = 3;
    if (add1(v[0]) != 4) return 1;
    return 42;
}
