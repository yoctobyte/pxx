{ SPDX-License-Identifier: Zlib }
unit gl_c;

{ OpenGL 3.3 core entry points, the subset lib/pcl's TGLArea demos need.

  A PASCAL unit, not a C header, for a measured reason: this was lib/pcl/gl_c.h
  until 2026-09-19, and a C header unit's library is derived from its FILE
  name, so every entry point below was imported from libgl_c.so, which does not
  exist. The compiler refuses such a build ("this build would die at exec"), and
  examples/gl/triangle was the one demo of 36 that could not build
  (bug-b-gl-triangle-demo-imports-gl-from-libgl-c-so-which-does-not-exist).
  A C header cannot name its library; an `external` clause can, which is the
  remedy that refusal prescribes.

  The library is libGL.so.1 (glvnd), which exports every core entry point
  directly and dispatches to the vendor of the current context, the one
  GtkGLArea made current. NOT libepoxy, as the old header's comment said:
  libepoxy exports `epoxy_glCreateShader` function pointers, not `glCreateShader`.

  The unit keeps its old name so `uses gl_c` sites need no change. }

interface

type
  GLenum    = LongWord;
  GLuint    = LongWord;
  GLint     = LongInt;
  GLsizei   = LongInt;
  GLfloat   = Single;
  GLboolean = Byte;

const
  GL_COLOR_BUFFER_BIT = $00004000;
  GL_DEPTH_BUFFER_BIT = $00000100;
  GL_DEPTH_TEST       = $0B71;
  GL_FALSE            = 0;
  GL_TRUE             = 1;
  GL_FLOAT            = $1406;
  GL_ARRAY_BUFFER     = $8892;
  GL_STATIC_DRAW      = $88E4;   { the old gl_c.h said $88B4, and glBufferData refused it with GL_INVALID_ENUM }
  GL_DYNAMIC_DRAW     = $88E8;
  GL_TRIANGLES        = $0004;
  GL_TRIANGLE_STRIP   = $0005;
  GL_VERTEX_SHADER    = $8B31;
  GL_FRAGMENT_SHADER  = $8B30;
  GL_COMPILE_STATUS   = $8B81;
  GL_LINK_STATUS      = $8B82;
  GL_INFO_LOG_LENGTH  = $8B84;

{ State }
procedure glEnable(cap: GLenum); cdecl; external 'libGL.so.1';
procedure glDisable(cap: GLenum); cdecl; external 'libGL.so.1';
procedure glViewport(x, y: GLint; width, height: GLsizei); cdecl; external 'libGL.so.1';
procedure glClearColor(r, g, b, a: GLfloat); cdecl; external 'libGL.so.1';
procedure glClear(mask: GLenum); cdecl; external 'libGL.so.1';

{ VAO }
procedure glGenVertexArrays(n: GLsizei; arrays: Pointer); cdecl; external 'libGL.so.1';
procedure glBindVertexArray(array_: GLuint); cdecl; external 'libGL.so.1';
procedure glDeleteVertexArrays(n: GLsizei; arrays: Pointer); cdecl; external 'libGL.so.1';

{ VBO }
procedure glGenBuffers(n: GLsizei; buffers: Pointer); cdecl; external 'libGL.so.1';
procedure glBindBuffer(target: GLenum; buffer: GLuint); cdecl; external 'libGL.so.1';
procedure glBufferData(target: GLenum; size: PtrInt; data: Pointer; usage: GLenum); cdecl; external 'libGL.so.1';
procedure glDeleteBuffers(n: GLsizei; buffers: Pointer); cdecl; external 'libGL.so.1';

{ Vertex attribs }
procedure glVertexAttribPointer(index: GLuint; size: GLint; type_: GLenum;
  normalized: GLboolean; stride: GLsizei; ptr: Pointer); cdecl; external 'libGL.so.1';
procedure glEnableVertexAttribArray(index: GLuint); cdecl; external 'libGL.so.1';

{ Shaders }
function  glCreateShader(type_: GLenum): GLuint; cdecl; external 'libGL.so.1';
procedure glShaderSource(shader: GLuint; count: GLsizei; strings: Pointer; lengths: Pointer); cdecl; external 'libGL.so.1';
procedure glCompileShader(shader: GLuint); cdecl; external 'libGL.so.1';
procedure glGetShaderiv(shader: GLuint; pname: GLenum; params: Pointer); cdecl; external 'libGL.so.1';
procedure glGetShaderInfoLog(shader: GLuint; bufSize: GLsizei; length: Pointer; infoLog: Pointer); cdecl; external 'libGL.so.1';
procedure glDeleteShader(shader: GLuint); cdecl; external 'libGL.so.1';

{ Programs }
function  glCreateProgram: GLuint; cdecl; external 'libGL.so.1';
procedure glAttachShader(prog, shader: GLuint); cdecl; external 'libGL.so.1';
procedure glLinkProgram(prog: GLuint); cdecl; external 'libGL.so.1';
procedure glGetProgramiv(prog: GLuint; pname: GLenum; params: Pointer); cdecl; external 'libGL.so.1';
procedure glGetProgramInfoLog(prog: GLuint; bufSize: GLsizei; length: Pointer; infoLog: Pointer); cdecl; external 'libGL.so.1';
procedure glUseProgram(prog: GLuint); cdecl; external 'libGL.so.1';
procedure glDeleteProgram(prog: GLuint); cdecl; external 'libGL.so.1';

{ Uniforms }
function  glGetUniformLocation(prog: GLuint; name: PChar): GLint; cdecl; external 'libGL.so.1';
procedure glUniformMatrix4fv(location: GLint; count: GLsizei; transpose: GLboolean; value: Pointer); cdecl; external 'libGL.so.1';
procedure glUniform1f(location: GLint; v0: GLfloat); cdecl; external 'libGL.so.1';
procedure glUniform2f(location: GLint; v0, v1: GLfloat); cdecl; external 'libGL.so.1';

{ Draw }
procedure glDrawArrays(mode: GLenum; first: GLint; count: GLsizei); cdecl; external 'libGL.so.1';

implementation

end.
