#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

#include <cstdlib>

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  guint inhibit_cookie;
  // --background: kompyuter yoqilganda yashirin ishga tushadi (pult serveri
  // ishlab turadi), televizor (ikkinchi ekran) ulanganda paydo bo‘ladi.
  gboolean background;
  int monitors;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Televizor qaysi monitor: TELEFON_TV_MONITOR=<raqam> bo‘lsa — o‘sha,
// aks holda jismonan eng katta ekran (32" televizor noutbuk yoki oddiy
// monitordan katta), teng bo‘lsa — asosiy bo‘lmagani (HDMI).
static int pick_monitor(GdkDisplay* display) {
  const int n = gdk_display_get_n_monitors(display);
  const char* env = g_getenv("TELEFON_TV_MONITOR");
  if (env != nullptr && *env != '\0') {
    const int i = atoi(env);
    if (i >= 0 && i < n) return i;
  }
  int best = 0;
  int best_mm = -1;
  for (int i = 0; i < n; i++) {
    GdkMonitor* m = gdk_display_get_monitor(display, i);
    const int mm = gdk_monitor_get_width_mm(m);
    const bool better = mm > best_mm ||
                        (mm == best_mm && !gdk_monitor_is_primary(m));
    if (better) {
      best = i;
      best_mm = mm;
    }
  }
  return best;
}

// Telefon TV televizorda to‘liq ekranda ochiladi; noutbuk ekrani bo‘sh qoladi,
// ya’ni kompyuterda ishlashda davom etish mumkin.
// TELEFON_TV_WINDOWED=1 — oddiy oynada (sinash uchun).
static void place_on_tv(MyApplication* self) {
  GtkWindow* window = self->window;
  if (window == nullptr || g_getenv("TELEFON_TV_WINDOWED") != nullptr) return;
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  const int index = pick_monitor(display);
  GdkMonitor* monitor = gdk_display_get_monitor(display, index);
  if (monitor != nullptr) {
    GdkRectangle area;
    gdk_monitor_get_geometry(monitor, &area);
    gtk_window_move(window, area.x, area.y);
    gtk_window_resize(window, area.width, area.height);
  }
  gtk_window_fullscreen_on_monitor(window, gtk_window_get_screen(window), index);
  if (g_getenv("TELEFON_TV_DEBUG") != nullptr) {
    g_message("Telefon TV: %d ta monitor, televizor — %d", gdk_display_get_n_monitors(display), index);
  }
}

static void set_awake(MyApplication* self, bool on) {
  if (on && self->inhibit_cookie == 0) {
    // Televizorda ko‘rsatayotganda ekran o‘chmasin, kompyuter uxlamasin.
    self->inhibit_cookie = gtk_application_inhibit(
        GTK_APPLICATION(self), self->window,
        static_cast<GtkApplicationInhibitFlags>(GTK_APPLICATION_INHIBIT_IDLE |
                                                GTK_APPLICATION_INHIBIT_SUSPEND),
        "Telefon TV televizorda ko‘rsatmoqda");
  } else if (!on && self->inhibit_cookie != 0) {
    gtk_application_uninhibit(GTK_APPLICATION(self), self->inhibit_cookie);
    self->inhibit_cookie = 0;
  }
}

// Oynani ko‘rsatish yoki (fon rejimida, televizor yo‘q bo‘lsa) yashirish.
static void update_visibility(MyApplication* self) {
  GtkWindow* window = self->window;
  if (window == nullptr) return;
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  const bool tv_connected = gdk_display_get_n_monitors(display) > 1;
  if (self->background && !tv_connected) {
    gtk_widget_hide(GTK_WIDGET(window));
    set_awake(self, false);
    return;
  }
  gtk_widget_show(GTK_WIDGET(window));
  place_on_tv(self);
  set_awake(self, true);
}

// HDMI keyinroq ulansa yoki uzilsa — oynani qayta joylashtiramiz.
static void monitors_changed_cb(GdkDisplay* display, GdkMonitor* monitor,
                                MyApplication* self) {
  self->monitors = gdk_display_get_n_monitors(display);
  update_visibility(self);
}

// Zaxira: ba’zi tizimlar monitor signalini yubormaydi — har 3 soniyada
// monitorlar sonini tekshiramiz.
static gboolean poll_monitors_cb(gpointer data) {
  MyApplication* self = MY_APPLICATION(data);
  if (self->window == nullptr) return G_SOURCE_REMOVE;
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(self->window));
  const int n = gdk_display_get_n_monitors(display);
  if (n != self->monitors) {
    self->monitors = n;
    update_visibility(self);
  }
  return G_SOURCE_CONTINUE;
}

static void window_destroyed_cb(MyApplication* self, GtkWidget* window) {
  g_signal_handlers_disconnect_by_data(gtk_widget_get_display(window), self);
  self->window = nullptr;
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView *view)
{
  self->monitors = gdk_display_get_n_monitors(gtk_widget_get_display(GTK_WIDGET(view)));
  update_visibility(self);
  g_timeout_add_seconds(3, poll_monitors_cb, self);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Telefon TV");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Telefon TV");
  }

  gtk_window_set_default_size(window, 1280, 720);
  gtk_window_set_icon_name(window, "telefon-tv");

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000 for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  g_signal_connect(display, "monitor-added", G_CALLBACK(monitors_changed_cb), self);
  g_signal_connect(display, "monitor-removed", G_CALLBACK(monitors_changed_cb), self);
  g_signal_connect_swapped(window, "destroy", G_CALLBACK(window_destroyed_cb), self);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);
  for (char** a = *arguments + 1; *a != nullptr; a++) {
    if (g_strcmp0(*a, "--background") == 0) self->background = TRUE;
  }

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->window = nullptr;
  self->inhibit_cookie = 0;
  self->background = FALSE;
  self->monitors = 0;
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
