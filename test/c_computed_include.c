/* A computed include (C 6.10.2p4): the #include operand is a macro that
   expands to <...> or "...". pxx used to include nothing at all for this,
   silently, so LVGL (`#include LV_STDINT_INCLUDE`) lost int64_t and bool.
   int64_t and bool below come ONLY from the computed includes. */
#define MY_STDINT_INCLUDE  <stdint.h>
#define MY_STDBOOL_INCLUDE <stdbool.h>
#define STR_(x) #x
#define STR(x) STR_(x)
#define LOCAL_NAME c_computed_include.h
#include MY_STDINT_INCLUDE
#include MY_STDBOOL_INCLUDE
#include STR(LOCAL_NAME)

int64_t big = 5000000000LL;
bool flag = true;

int printf(const char *, ...);
int main(void)
{
    printf("computed include %lld %d %d\n", (long long)big, (int)flag, COMPUTED_HEADER_VALUE);
    return 0;
}
