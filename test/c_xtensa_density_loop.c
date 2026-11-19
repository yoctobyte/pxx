/* The loop of feature-xtensa-codegen-density-before-register-allocation:
   tools/check_xtensa_density.py counts f's instructions on windowed xtensa.
   It was 74 (every operand through the expression stack, the condition
   materialised as 0/1 and compared against 0, i++ through an address temp
   and two more slots). */
int f(int a, int b)
{
    int s = 0, i;
    for (i = 0; i < a; i++)
        s += i * b;
    return s;
}
