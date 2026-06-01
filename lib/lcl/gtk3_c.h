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

// Dialogs
void* gtk_message_dialog_new(void* parent, int flags, int mtype, int buttons, char* fmt, char* msg);
int gtk_dialog_run(void* dialog);

// Libc
int usleep(unsigned int usec);

#endif
