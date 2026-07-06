/* Regression: scalar global initializers that are constant EXPRESSIONS, not bare
   literals — a cast, arithmetic, or an integer literal assigned to a float —
   were skipped (left 0). Now folded via the const evaluator. Returns 42. */
typedef int myint;
myint a = (myint)7;        /* cast in global init */
int b = 2 + 3 * 4;         /* arithmetic const */
double c = 100;            /* int literal -> double */
double d = (double)42;     /* cast to double */
float  e = 5;              /* int literal -> float */
int main(void) {
    if (a != 7) return 1;
    if (b != 14) return 2;
    if (c < 99.5 || c > 100.5) return 3;
    if (d < 41.5 || d > 42.5) return 4;
    if (e < 4.5 || e > 5.5) return 5;
    return 42;
}
