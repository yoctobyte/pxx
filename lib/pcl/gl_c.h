#ifndef GL_C_H
#define GL_C_H

/* GtkGLArea widget — requires GTK 3.16+, linked via libgtk-3.so.0 */
void* gtk_gl_area_new(void);
void  gtk_gl_area_set_required_version(void* gl_area, int major, int minor);
void  gtk_gl_area_set_use_es(void* gl_area, int use_es);
void  gtk_gl_area_make_current(void* gl_area);
void* gtk_gl_area_get_error(void* gl_area);
void  gtk_gl_area_queue_render(void* gl_area);
int   gtk_widget_get_allocated_width(void* widget);
int   gtk_widget_get_allocated_height(void* widget);

/* ------------------------------------------------------------------ */
/* OpenGL 3.3 core — dispatched by libepoxy (loads GL entry points     */
/* automatically at first call, no glXGetProcAddress needed).          */
/* ------------------------------------------------------------------ */

/* GL constants */
#define GL_COLOR_BUFFER_BIT   0x00004000
#define GL_DEPTH_BUFFER_BIT   0x00000100
#define GL_DEPTH_TEST         0x0B71
#define GL_FALSE              0
#define GL_TRUE               1
#define GL_FLOAT              0x1406
#define GL_ARRAY_BUFFER       0x8892
#define GL_STATIC_DRAW        0x88B4
#define GL_DYNAMIC_DRAW       0x88E8
#define GL_TRIANGLES          0x0004
#define GL_TRIANGLE_STRIP     0x0005
#define GL_VERTEX_SHADER      0x8B31
#define GL_FRAGMENT_SHADER    0x8B30
#define GL_COMPILE_STATUS     0x8B81
#define GL_LINK_STATUS        0x8B82
#define GL_INFO_LOG_LENGTH    0x8B84

typedef unsigned int GLenum;
typedef unsigned int GLuint;
typedef int          GLint;
typedef int          GLsizei;
typedef float        GLfloat;
typedef char         GLchar;

/* State */
void glEnable(GLenum cap);
void glDisable(GLenum cap);
void glViewport(GLint x, GLint y, GLsizei width, GLsizei height);
void glClearColor(GLfloat r, GLfloat g, GLfloat b, GLfloat a);
void glClear(GLenum mask);

/* VAO */
void glGenVertexArrays(GLsizei n, GLuint* arrays);
void glBindVertexArray(GLuint array_);
void glDeleteVertexArrays(GLsizei n, GLuint* arrays);

/* VBO */
void glGenBuffers(GLsizei n, GLuint* buffers);
void glBindBuffer(GLenum target, GLuint buffer);
void glBufferData(GLenum target, int size, void* data, GLenum usage);
void glDeleteBuffers(GLsizei n, GLuint* buffers);

/* Vertex attribs */
void glVertexAttribPointer(GLuint index, GLint size, GLenum type,
                           unsigned char normalized, GLsizei stride, void* pointer);
void glEnableVertexAttribArray(GLuint index);

/* Shaders */
GLuint glCreateShader(GLenum type);
void   glShaderSource(GLuint shader, GLsizei count, char** string_, int* length);
void   glCompileShader(GLuint shader);
void   glGetShaderiv(GLuint shader, GLenum pname, GLint* params);
void   glGetShaderInfoLog(GLuint shader, GLsizei bufSize, GLsizei* length, GLchar* infoLog);
void   glDeleteShader(GLuint shader);

/* Programs */
GLuint glCreateProgram(void);
void   glAttachShader(GLuint program, GLuint shader);
void   glLinkProgram(GLuint program);
void   glGetProgramiv(GLuint program, GLenum pname, GLint* params);
void   glGetProgramInfoLog(GLuint program, GLsizei bufSize, GLsizei* length, GLchar* infoLog);
void   glUseProgram(GLuint program);
void   glDeleteProgram(GLuint program);

/* Uniforms */
GLint glGetUniformLocation(GLuint program, GLchar* name);
void  glUniformMatrix4fv(GLint location, GLsizei count, unsigned char transpose, GLfloat* value);
void  glUniform1f(GLint location, GLfloat v0);
void  glUniform2f(GLint location, GLfloat v0, GLfloat v1);

/* Draw */
void glDrawArrays(GLenum mode, GLint first, GLsizei count);

/* Math from libc */
float  sinf(float x);
float  cosf(float x);

#endif
