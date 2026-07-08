/* cglm probe (game-library ladder): header-only C graphics math, plain-C
   paths (no SSE/NEON — pxx defines no SIMD macros). mat4 multiply +
   vec3 ops, deterministic, exit 42. */
#include <cglm/cglm.h>

int printf(const char *, ...);

int main(void) {
    mat4 a = GLM_MAT4_IDENTITY_INIT, b = GLM_MAT4_IDENTITY_INIT, c;
    vec3 v = {1.0f, 2.0f, 3.0f}, w;
    a[3][0] = 5.0f;              /* translation x */
    b[3][1] = -2.0f;             /* translation y */
    glm_mat4_mul(a, b, c);
    if (c[3][0] != 5.0f || c[3][1] != -2.0f || c[3][3] != 1.0f) return 1;
    glm_vec3_scale(v, 2.0f, w);
    if (w[0] != 2.0f || w[1] != 4.0f || w[2] != 6.0f) return 2;
    if (glm_vec3_dot(v, v) != 14.0f) return 3;
    return 42;
}
