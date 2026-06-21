/* Probe: compile a tiny program that calls a crtl function.
 * Expected to GAP until the C body frontend (feature-c-source-frontend) lands. */
#include <string.h>

int main(void) {
    return strlen("abc");
}
