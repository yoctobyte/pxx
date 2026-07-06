/* Regression: #pragma push_macro / pop_macro save & restore a macro definition
   on a per-name stack (C_GCC/MSVC extension). A user macro also named
   push_macro/pop_macro must not interfere. Returns 42. */
#define push_macro decoy1
#define pop_macro  decoy2
#define X 111
#pragma push_macro("X")
#undef X
#define X 222
#pragma push_macro("X")
#undef X
#define X 333
int main(void) {
    int a = X;                     /* 333 */
    #pragma pop_macro("X")
    int b = X;                     /* 222 */
    #pragma pop_macro("X")
    int c = X;                     /* 111 */
    return (a == 333 && b == 222 && c == 111) ? 42 : 1;
}
