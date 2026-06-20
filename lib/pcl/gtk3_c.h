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
void* gtk_widget_get_parent(void* widget);
void gtk_widget_set_size_request(void* widget, int width, int height);
void* gtk_bin_get_child(void* bin);

// Dialogs
void* gtk_message_dialog_new(void* parent, int flags, int mtype, int buttons, char* fmt, char* msg);
int gtk_dialog_run(void* dialog);

// Timer source removal
int g_source_remove(unsigned int tag);

// Scrolled Window & Text View (TMemo)
#define GTK_POLICY_ALWAYS 0
#define GTK_POLICY_AUTOMATIC 1
#define GTK_POLICY_NEVER 2

void* gtk_scrolled_window_new(void* hadjustment, void* vadjustment);
void gtk_scrolled_window_set_policy(void* scrolled_window, int hpolicy, int vpolicy);
void* gtk_text_view_new(void);
void* gtk_text_view_get_buffer(void* text_view);
void gtk_text_buffer_set_text(void* buffer, char* text, int len);
char* gtk_text_buffer_get_text(void* buffer, void* start, void* end, int include_hidden);
void gtk_text_buffer_get_start_iter(void* buffer, void* iter);
void gtk_text_buffer_get_end_iter(void* buffer, void* iter);

// List Box (TListBox)
void* gtk_list_box_new(void);
void* gtk_list_box_row_new(void);
void gtk_list_box_insert(void* list_box, void* widget, int position);
void* gtk_list_box_get_selected_row(void* list_box);
int gtk_list_box_row_get_index(void* row);
void* gtk_list_box_get_row_at_index(void* list_box, int index_);
void gtk_list_box_select_row(void* list_box, void* row);

// Combo Box (TComboBox)
void* gtk_combo_box_text_new(void);
void gtk_combo_box_text_append_text(void* combo_box_text, char* text);
int gtk_combo_box_get_active(void* combo_box);
void gtk_combo_box_set_active(void* combo_box, int index_);
void gtk_combo_box_text_remove_all(void* combo_box_text);

// Drawing Area (TPaintBox)
void* gtk_drawing_area_new(void);

// Cairo drawing functions
void cairo_save(void* cr);
void cairo_restore(void* cr);
void cairo_translate(void* cr, double tx, double ty);
void cairo_scale(void* cr, double sx, double sy);
void cairo_move_to(void* cr, double x, double y);
void cairo_line_to(void* cr, double x, double y);
void cairo_stroke(void* cr);
void cairo_set_source_rgb(void* cr, double r, double g, double b);
void cairo_set_line_width(void* cr, double width);
void cairo_rectangle(void* cr, double x, double y, double width, double height);
void cairo_fill(void* cr);
void cairo_fill_preserve(void* cr);
void cairo_arc(void* cr, double xc, double yc, double radius, double angle1, double angle2);
void cairo_select_font_face(void* cr, char* family, int slant, int weight);
void cairo_set_font_size(void* cr, double size);
void cairo_show_text(void* cr, char* utf8);

// Menus
void* gtk_menu_bar_new(void);
void* gtk_menu_new(void);
void* gtk_menu_item_new_with_label(char* label);
void* gtk_menu_item_new_with_mnemonic(char* label);
void gtk_menu_item_set_submenu(void* menu_item, void* submenu);
void gtk_menu_shell_append(void* menu_shell, void* menu_item);
void gtk_menu_item_activate(void* menu_item);

// Box & Container Layout
void* gtk_box_new(int orientation, int spacing);
void gtk_box_pack_start(void* box, void* child, int expand, int fill, unsigned int padding);
void gtk_box_reorder_child(void* box, void* child, int position);
void gtk_container_remove(void* container, void* widget);

// Widget name (used for data association)
void gtk_widget_set_name(void* widget, char* name);
char* gtk_widget_get_name(void* widget);

// Widget visibility
void gtk_widget_show(void* widget);

// Libc
int usleep(unsigned int usec);

#endif


