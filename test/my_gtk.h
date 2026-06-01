#ifndef MY_GTK_H
#define MY_GTK_H

#define G_GNUC_INTERNAL __attribute__((visibility("hidden")))
#define G_GNUC_WARN_UNUSED_RESULT __attribute__((warn_unused_result))

typedef unsigned int guint;
typedef int gint;
typedef char gchar;
typedef void* gpointer;

// Test GObject macro soup and attributes
#define G_DECLARE_FINAL_TYPE(ModuleObjName, module_obj_name, MODULE, OBJ_NAME, ParentName) \
  typedef struct _##ModuleObjName ModuleObjName; \
  G_GNUC_INTERNAL ModuleObjName *module_obj_name##_get_type(void);

// Test attribute discarding and alignment in struct
struct _GtkButton {
  gint width __attribute__((aligned(8)));
  gint height;
  gchar active;
};

// Test function-like macros and recursive expansion
#define GTK_BUTTON(obj) ((GtkButton*)(obj))
#define GTK_IS_BUTTON(obj) (obj != 0)

// Function prototypes to parse
G_GNUC_WARN_UNUSED_RESULT
gint gtk_button_get_width(gpointer button);

G_GNUC_WARN_UNUSED_RESULT
gint gtk_button_get_height(gpointer button);

#endif
