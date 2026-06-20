#ifndef GTK3_C_H
#define GTK3_C_H

typedef void* PGtkWidget;

#define GTK_WINDOW_TOPLEVEL 0
#define GTK_MESSAGE_INFO 0
#define GTK_MESSAGE_WARNING 1
#define GTK_MESSAGE_QUESTION 2
#define GTK_MESSAGE_ERROR 3
#define GTK_BUTTONS_NONE 0
#define GTK_BUTTONS_OK 1
#define GTK_DIALOG_MODAL 1
#define GTK_DIALOG_DESTROY_WITH_PARENT 2

// Lifecycle
void gtk_init(void* argc, void* argv);
int gtk_get_major_version(void);
int gtk_get_minor_version(void);
int gtk_get_micro_version(void);

// Event loop
void gtk_main(void);
void gtk_main_quit(void);
int gtk_events_pending(void);
int gtk_main_iteration_do(int blocking);

// Signals
unsigned int g_signal_connect_data(void* instance, char* signal, void* handler, void* data, void* destroy, int flags);
unsigned int g_timeout_add(unsigned int interval, void* func, void* data);

// Widgets
void* gtk_window_new(int wtype);
void gtk_window_set_title(void* window, char* title);
void gtk_window_set_default_size(void* window, int w, int h);
void* gtk_button_new_with_label(char* label_);
void gtk_button_set_label(void* button, char* label_);
void gtk_button_clicked(void* button);
void gtk_container_add(void* container, void* widget);
void gtk_widget_show_all(void* widget);
void gtk_widget_destroy(void* widget);

// Additional Widgets & Layout
void* gtk_label_new(char* text);
void gtk_label_set_text(void* label, char* text);
void* gtk_entry_new(void);
void gtk_entry_set_text(void* entry, char* text);
char* gtk_entry_get_text(void* entry);
void* gtk_check_button_new_with_label(char* label);
int gtk_toggle_button_get_active(void* toggle_button);
void gtk_toggle_button_set_active(void* toggle_button, int is_active);
void* gtk_frame_new(char* label);
void* gtk_fixed_new(void);
void gtk_fixed_put(void* container, void* widget, int x, int y);
void gtk_fixed_move(void* container, void* widget, int x, int y);
void gtk_widget_set_size_request(void* widget, int width, int height);
void* gtk_bin_get_child(void* bin);

// Dialogs
void* gtk_message_dialog_new(void* parent, int flags, int mtype, int buttons, char* fmt, char* msg);
int gtk_dialog_run(void* dialog);

// Timer source removal
int g_source_remove(unsigned int tag);

// Libc
int usleep(unsigned int usec);

#endif

