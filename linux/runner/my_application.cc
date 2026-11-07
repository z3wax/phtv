#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <webkit2/webkit2.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <initializer_list>
#include <memory>
#include <string>

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  guint inhibit_cookie;
  // --background: kompyuter yoqilganda yashirin ishga tushadi (pult serveri
  // ishlab turadi), televizor (ikkinchi ekran) ulanganda paydo bo‘ladi.
  gboolean background;
  int monitors;
  FlMethodChannel* channel;
  FlMethodChannel* browser_channel;
  GtkOverlay* overlay;
  FlView* flutter_view;
  GHashTable* browsers;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// WebKitGTK is an ordinary child of this application's GTK window. The bounded
// overlay keeps Flutter's address bar and TV controls visible above the page.
struct BrowserView {
  MyApplication* application;
  int64_t id;
  WebKitWebView* view;
  GdkRectangle bounds;
  gboolean visible;
  gboolean muted_before_hide;
};

static BrowserView* browser_find(MyApplication* self, int64_t id) {
  return static_cast<BrowserView*>(g_hash_table_lookup(self->browsers, &id));
}

static FlValue* browser_arg(FlValue* args, const char* name) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return nullptr;
  return fl_value_lookup_string(args, name);
}

static const char* browser_string(FlValue* args, const char* name,
                                  const char* fallback = "") {
  FlValue* value = browser_arg(args, name);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(value) : fallback;
}

static double browser_number(FlValue* args, const char* name, double fallback = 0) {
  FlValue* value = browser_arg(args, name);
  if (value == nullptr) return fallback;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) return fl_value_get_float(value);
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) return fl_value_get_int(value);
  return fallback;
}

static gboolean browser_boolean(FlValue* args, const char* name, gboolean fallback) {
  FlValue* value = browser_arg(args, name);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL
             ? fl_value_get_bool(value) : fallback;
}

static void browser_event(BrowserView* browser, const char* type,
                           const char* error = nullptr, const char* key = nullptr) {
  MyApplication* self = browser->application;
  if (self->browser_channel == nullptr) return;
  g_autoptr(FlValue) event = fl_value_new_map();
  fl_value_set_string_take(event, "id", fl_value_new_int(browser->id));
  fl_value_set_string_take(event, "type", fl_value_new_string(type));
  const gchar* uri = webkit_web_view_get_uri(browser->view);
  const gchar* title = webkit_web_view_get_title(browser->view);
  fl_value_set_string_take(event, "url", fl_value_new_string(uri == nullptr ? "" : uri));
  fl_value_set_string_take(event, "title", fl_value_new_string(title == nullptr ? "" : title));
  fl_value_set_string_take(event, "progress", fl_value_new_int(
      static_cast<int>(webkit_web_view_get_estimated_load_progress(browser->view) * 100)));
  if (error != nullptr) fl_value_set_string_take(event, "error", fl_value_new_string(error));
  if (key != nullptr) fl_value_set_string_take(event, "key", fl_value_new_string(key));
  fl_method_channel_invoke_method(self->browser_channel, "event", event,
                                  nullptr, nullptr, nullptr);
}

static gboolean browser_position_cb(GtkOverlay* overlay, GtkWidget* child,
                                     GdkRectangle* allocation, gpointer data) {
  MyApplication* self = MY_APPLICATION(data);
  GHashTableIter iterator;
  gpointer value;
  g_hash_table_iter_init(&iterator, self->browsers);
  while (g_hash_table_iter_next(&iterator, nullptr, &value)) {
    BrowserView* browser = static_cast<BrowserView*>(value);
    if (GTK_WIDGET(browser->view) != child) continue;
    GtkAllocation available;
    gtk_widget_get_allocation(GTK_WIDGET(overlay), &available);
    *allocation = browser->bounds;
    allocation->x = std::max(0, std::min(allocation->x, available.width));
    allocation->y = std::max(0, std::min(allocation->y, available.height));
    allocation->width = std::max(1, std::min(allocation->width, available.width - allocation->x));
    allocation->height = std::max(1, std::min(allocation->height, available.height - allocation->y));
    return TRUE;
  }
  return FALSE;
}

struct BrowserJavaScript {
  FlMethodCall* call;
  gboolean result;
};

static void browser_javascript_cb(GObject* source, GAsyncResult* result, gpointer data) {
  std::unique_ptr<BrowserJavaScript> invocation(static_cast<BrowserJavaScript*>(data));
  g_autoptr(GError) error = nullptr;
  g_autoptr(JSCValue) value = nullptr;
#if WEBKIT_CHECK_VERSION(2, 40, 0)
  value = webkit_web_view_evaluate_javascript_finish(WEBKIT_WEB_VIEW(source), result, &error);
#else
  WebKitJavascriptResult* javascript = webkit_web_view_run_javascript_finish(
      WEBKIT_WEB_VIEW(source), result, &error);
  if (javascript != nullptr) {
    value = JSC_VALUE(g_object_ref(webkit_javascript_result_get_js_value(javascript)));
    webkit_javascript_result_unref(javascript);
  }
#endif
  if (invocation->call != nullptr) {
    g_autoptr(FlMethodResponse) response = nullptr;
    if (error != nullptr) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("javascript", error->message, nullptr));
    } else if (invocation->result && value != nullptr) {
      g_autofree gchar* json = jsc_value_to_json(value, 0);
      g_autoptr(FlValue) text = fl_value_new_string(json == nullptr ? "null" : json);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(text));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
    fl_method_call_respond(invocation->call, response, nullptr);
    g_object_unref(invocation->call);
  }
}

static void browser_javascript(BrowserView* browser, const gchar* script,
                                FlMethodCall* call = nullptr, gboolean result = FALSE) {
  BrowserJavaScript* invocation = new BrowserJavaScript{
      call == nullptr ? nullptr : FL_METHOD_CALL(g_object_ref(call)), result};
#if WEBKIT_CHECK_VERSION(2, 40, 0)
  webkit_web_view_evaluate_javascript(browser->view, script, -1, nullptr, nullptr,
                                    nullptr, browser_javascript_cb, invocation);
#else
  webkit_web_view_run_javascript(browser->view, script, nullptr,
                                browser_javascript_cb, invocation);
#endif
}

static void browser_load_cb(WebKitWebView* view, WebKitLoadEvent event, gpointer data) {
  BrowserView* browser = static_cast<BrowserView*>(data);
  switch (event) {
    case WEBKIT_LOAD_STARTED: browser_event(browser, "started"); break;
    case WEBKIT_LOAD_FINISHED: browser_event(browser, "finished"); break;
    default: break;
  }
}

static void browser_notify_cb(GObject* object, GParamSpec* property, gpointer data) {
  BrowserView* browser = static_cast<BrowserView*>(data);
  const char* name = g_param_spec_get_name(property);
  if (g_strcmp0(name, "title") == 0) browser_event(browser, "title");
  if (g_strcmp0(name, "uri") == 0) browser_event(browser, "url");
  if (g_strcmp0(name, "estimated-load-progress") == 0) browser_event(browser, "progress");
}

static gboolean browser_load_failed_cb(WebKitWebView* view, WebKitLoadEvent event,
                                        gchar* uri, GError* error, gpointer data) {
  // A replaced or deliberately cancelled navigation is not a failed page.
  if (g_error_matches(error, WEBKIT_NETWORK_ERROR, WEBKIT_NETWORK_ERROR_CANCELLED)) return FALSE;
  browser_event(static_cast<BrowserView*>(data), "error", error->message);
  return FALSE;
}

static gboolean browser_policy_cb(WebKitWebView* view, WebKitPolicyDecision* decision,
                                   WebKitPolicyDecisionType type, gpointer data) {
  if (type != WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) return FALSE;
  WebKitNavigationPolicyDecision* navigation = WEBKIT_NAVIGATION_POLICY_DECISION(decision);
  WebKitNavigationAction* action = webkit_navigation_policy_decision_get_navigation_action(navigation);
  WebKitURIRequest* request = webkit_navigation_action_get_request(action);
  const gchar* uri = webkit_uri_request_get_uri(request);
  if (uri != nullptr) webkit_web_view_load_uri(view, uri);
  webkit_policy_decision_ignore(decision);
  return TRUE;
}

static GtkWidget* browser_create_cb(WebKitWebView* view, WebKitNavigationAction* action,
                                     gpointer data) {
  // window.open / target=_blank stay inside this application's current view.
  WebKitURIRequest* request = webkit_navigation_action_get_request(action);
  const gchar* uri = webkit_uri_request_get_uri(request);
  if (uri != nullptr) webkit_web_view_load_uri(view, uri);
  return nullptr;
}

static gboolean browser_fullscreen_cb(WebKitWebView* view, gpointer data) {
  // The TV application already owns fullscreen. Keep its remote controls and
  // address bar rather than allowing a web page to create another native mode.
  return TRUE;
}

static gboolean browser_key_cb(GtkWidget* widget, GdkEventKey* event, gpointer data) {
  BrowserView* browser = static_cast<BrowserView*>(data);
  if (event->send_event) return FALSE;
  const gchar* key = nullptr;
  switch (event->keyval) {
    case GDK_KEY_Escape: key = "escape"; break;
    case GDK_KEY_F6: key = "address"; break;
    case GDK_KEY_Home:
      if ((event->state & GDK_CONTROL_MASK) != 0) key = "home";
      break;
    default: break;
  }
  if (key == nullptr && (event->state & GDK_CONTROL_MASK) != 0 &&
      (event->keyval == GDK_KEY_l || event->keyval == GDK_KEY_L)) key = "address";
  if (key == nullptr) return FALSE;
  browser_event(browser, "key", nullptr, key);
  return TRUE;
}

static void browser_view_destroy(gpointer data) {
  BrowserView* browser = static_cast<BrowserView*>(data);
  g_signal_handlers_disconnect_by_data(browser->view, browser);
  gtk_widget_destroy(GTK_WIDGET(browser->view));
  g_object_unref(browser->view);
  delete browser;
}

static std::string javascript_string(const char* text) {
  std::string out = "\"";
  for (const unsigned char* c = reinterpret_cast<const unsigned char*>(text); *c; ++c) {
    switch (*c) {
      case '\\': out += "\\\\"; break;
      case '"': out += "\\\""; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (*c < 0x20) {
          gchar escape[7];
          g_snprintf(escape, sizeof(escape), "\\u%04x", *c);
          out += escape;
        } else {
          out += static_cast<char>(*c);
        }
    }
  }
  return out + "\"";
}

static void browser_send_key(BrowserView* browser, const gchar* name) {
  guint keyval = GDK_KEY_VoidSymbol;
  if (g_strcmp0(name, "up") == 0) keyval = GDK_KEY_Up;
  else if (g_strcmp0(name, "down") == 0) keyval = GDK_KEY_Down;
  else if (g_strcmp0(name, "left") == 0) keyval = GDK_KEY_Left;
  else if (g_strcmp0(name, "right") == 0) keyval = GDK_KEY_Right;
  else if (g_strcmp0(name, "enter") == 0 || g_strcmp0(name, "ok") == 0) keyval = GDK_KEY_Return;
  else if (g_strcmp0(name, "escape") == 0 || g_strcmp0(name, "back") == 0) keyval = GDK_KEY_Escape;
  else if (g_strcmp0(name, "space") == 0 || g_strcmp0(name, "playPause") == 0) keyval = GDK_KEY_space;
  else if (g_strcmp0(name, "backspace") == 0) keyval = GDK_KEY_BackSpace;
  else if (g_strcmp0(name, "tab") == 0) keyval = GDK_KEY_Tab;
  else if (g_strcmp0(name, "home") == 0) keyval = GDK_KEY_Home;
  else if (g_strcmp0(name, "end") == 0) keyval = GDK_KEY_End;
  else keyval = gdk_keyval_from_name(name);
  if (keyval == GDK_KEY_VoidSymbol) return;
  GtkWidget* widget = GTK_WIDGET(browser->view);
  gtk_widget_grab_focus(widget);
  GdkWindow* window = gtk_widget_get_window(widget);
  if (window == nullptr) return;
  GdkKeymapKey* keys = nullptr;
  gint key_count = 0;
  GdkKeymap* keymap = gdk_keymap_get_for_display(gtk_widget_get_display(widget));
  gdk_keymap_get_entries_for_keyval(keymap, keyval, &keys, &key_count);
  for (GdkEventType type : {GDK_KEY_PRESS, GDK_KEY_RELEASE}) {
    GdkEvent* event = gdk_event_new(type);
    event->key.window = GDK_WINDOW(g_object_ref(window));
    event->key.send_event = TRUE;
    event->key.time = GDK_CURRENT_TIME;
    event->key.keyval = keyval;
    event->key.hardware_keycode = key_count > 0 ? keys[0].keycode : 0;
    event->key.group = key_count > 0 ? keys[0].group : 0;
    const gunichar character = gdk_keyval_to_unicode(keyval);
    gchar utf8[8] = {0};
    if (character != 0) g_unichar_to_utf8(character, utf8);
    event->key.string = g_strdup(utf8);
    event->key.length = strlen(utf8);
    GdkSeat* seat = gdk_display_get_default_seat(gtk_widget_get_display(widget));
    if (seat != nullptr) {
      GdkDevice* keyboard = gdk_seat_get_keyboard(seat);
      if (keyboard != nullptr) gdk_event_set_device(event, keyboard);
    }
    gtk_widget_event(widget, event);
    gdk_event_free(event);
  }
  g_free(keys);
}

static void browser_pointer_event(BrowserView* browser, double fx, double fy,
                                   GdkEventType type) {
  GtkWidget* widget = GTK_WIDGET(browser->view);
  GdkWindow* window = gtk_widget_get_window(widget);
  if (window == nullptr) return;
  GtkAllocation area;
  gtk_widget_get_allocation(widget, &area);
  const double x = std::max(0.0, std::min(1.0, fx)) * std::max(1, area.width - 1);
  const double y = std::max(0.0, std::min(1.0, fy)) * std::max(1, area.height - 1);
  gint origin_x = 0, origin_y = 0;
  gdk_window_get_origin(window, &origin_x, &origin_y);
  GdkEvent* event = gdk_event_new(type);
  if (type == GDK_MOTION_NOTIFY) {
    event->motion.window = GDK_WINDOW(g_object_ref(window));
    event->motion.send_event = TRUE;
    event->motion.time = GDK_CURRENT_TIME;
    event->motion.x = x;
    event->motion.y = y;
    event->motion.x_root = origin_x + x;
    event->motion.y_root = origin_y + y;
  } else {
    event->button.window = GDK_WINDOW(g_object_ref(window));
    event->button.send_event = TRUE;
    event->button.time = GDK_CURRENT_TIME;
    event->button.x = x;
    event->button.y = y;
    event->button.x_root = origin_x + x;
    event->button.y_root = origin_y + y;
    event->button.button = GDK_BUTTON_PRIMARY;
    event->button.state = type == GDK_BUTTON_RELEASE ? GDK_BUTTON1_MASK : 0;
  }
  GdkSeat* seat = gdk_display_get_default_seat(gtk_widget_get_display(widget));
  if (seat != nullptr) {
    GdkDevice* pointer = gdk_seat_get_pointer(seat);
    if (pointer != nullptr) gdk_event_set_device(event, pointer);
  }
  gdk_event_put(event);
  gdk_event_free(event);
}

static void browser_method_cb(FlMethodChannel* channel, FlMethodCall* call,
                               gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  const int64_t id = static_cast<int64_t>(browser_number(args, "id"));
  BrowserView* browser = browser_find(self, id);
  g_autoptr(FlMethodResponse) response = nullptr;
  g_autoptr(FlValue) result = nullptr;
  if (g_strcmp0(method, "create") == 0 && self->overlay != nullptr) {
    if (browser != nullptr) g_hash_table_remove(self->browsers, &id);
    WebKitWebContext* context = webkit_web_context_get_default();
    WebKitCookieManager* cookies = webkit_web_context_get_cookie_manager(context);
    g_autofree gchar* data_dir = g_build_filename(g_get_user_data_dir(), "telefon-tv", "browser", nullptr);
    g_mkdir_with_parents(data_dir, 0700);
    g_autofree gchar* cookie_file = g_build_filename(data_dir, "cookies.sqlite", nullptr);
    webkit_cookie_manager_set_persistent_storage(cookies, cookie_file, WEBKIT_COOKIE_PERSISTENT_STORAGE_SQLITE);
    WebKitWebView* view = WEBKIT_WEB_VIEW(webkit_web_view_new_with_context(context));
    g_object_ref_sink(view);
    // A route can load before its opening transition has made it visible.
    webkit_web_view_set_is_muted(view, TRUE);
    WebKitUserScript* remote_input = webkit_user_script_new(R"JS(
      addEventListener('message', function(event) {
        var d=event.data;
        if(event.source!==parent || !d || d.telefonTvRemoteClick!==true) return;
        var x=d.fx*innerWidth,y=d.fy*innerHeight,e=document.elementFromPoint(x,y);
        if(!e) return;
        if(e.tagName==='IFRAME') {
          var r=e.getBoundingClientRect();
          e.contentWindow.postMessage({telefonTvRemoteClick:true,fx:(x-r.left)/r.width,fy:(y-r.top)/r.height},'*');
        } else {
          e.focus();
          ['mousedown','mouseup'].forEach(function(n){e.dispatchEvent(new MouseEvent(n,{bubbles:true,clientX:x,clientY:y}));});
          e.click();
        }
      });
    )JS", WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES,
      WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, nullptr, nullptr);
    webkit_user_content_manager_add_script(webkit_web_view_get_user_content_manager(view), remote_input);
    webkit_user_script_unref(remote_input);
    WebKitSettings* settings = webkit_web_view_get_settings(view);
    webkit_settings_set_enable_javascript(settings, TRUE);
    webkit_settings_set_media_playback_requires_user_gesture(settings, FALSE);
    webkit_settings_set_enable_fullscreen(settings, TRUE);
    const gchar* user_agent = browser_string(args, "userAgent");
    if (*user_agent != '\0') webkit_settings_set_user_agent(settings, user_agent);
    GdkRGBA black = {0, 0, 0, 1};
    webkit_web_view_set_background_color(view, &black);
    browser = new BrowserView{self, id, view, {0, 0, 1, 1}, FALSE, FALSE};
    int64_t* key = g_new(int64_t, 1);
    *key = id;
    g_hash_table_insert(self->browsers, key, browser);
    gtk_widget_set_no_show_all(GTK_WIDGET(view), TRUE);
    gtk_overlay_add_overlay(self->overlay, GTK_WIDGET(view));
    g_signal_connect(view, "load-changed", G_CALLBACK(browser_load_cb), browser);
    g_signal_connect(view, "load-failed", G_CALLBACK(browser_load_failed_cb), browser);
    g_signal_connect(view, "notify::title", G_CALLBACK(browser_notify_cb), browser);
    g_signal_connect(view, "notify::uri", G_CALLBACK(browser_notify_cb), browser);
    g_signal_connect(view, "notify::estimated-load-progress", G_CALLBACK(browser_notify_cb), browser);
    g_signal_connect(view, "decide-policy", G_CALLBACK(browser_policy_cb), browser);
    g_signal_connect(view, "create", G_CALLBACK(browser_create_cb), browser);
    g_signal_connect(view, "enter-fullscreen", G_CALLBACK(browser_fullscreen_cb), browser);
    g_signal_connect(view, "leave-fullscreen", G_CALLBACK(browser_fullscreen_cb), browser);
    g_signal_connect(view, "key-press-event", G_CALLBACK(browser_key_cb), browser);
  } else if (g_strcmp0(method, "dispose") == 0) {
    g_hash_table_remove(self->browsers, &id);
  } else if (browser == nullptr) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new("browser_closed", "Brauzer yopilgan", nullptr));
  } else if (g_strcmp0(method, "load") == 0) {
    webkit_web_view_load_uri(browser->view, browser_string(args, "url"));
  } else if (g_strcmp0(method, "runJavaScript") == 0) {
    browser_javascript(browser, browser_string(args, "script"), call,
                       browser_boolean(args, "result", FALSE));
    return;
  } else if (g_strcmp0(method, "canGoBack") == 0) {
    result = fl_value_new_bool(webkit_web_view_can_go_back(browser->view));
  } else if (g_strcmp0(method, "goBack") == 0) {
    if (webkit_web_view_can_go_back(browser->view)) webkit_web_view_go_back(browser->view);
  } else if (g_strcmp0(method, "reload") == 0) {
    webkit_web_view_reload(browser->view);
  } else if (g_strcmp0(method, "setBounds") == 0) {
    browser->bounds = {
      static_cast<int>(browser_number(args, "x")),
      static_cast<int>(browser_number(args, "y")),
      std::max(1, static_cast<int>(browser_number(args, "width", 1))),
      std::max(1, static_cast<int>(browser_number(args, "height", 1)))};
    gtk_widget_queue_resize(GTK_WIDGET(self->overlay));
  } else if (g_strcmp0(method, "setVisible") == 0) {
    const gboolean visible = browser_boolean(args, "visible", FALSE);
    if (visible != browser->visible) {
      browser->visible = visible;
      if (visible) {
        webkit_web_view_set_is_muted(browser->view, browser->muted_before_hide);
        gtk_widget_show(GTK_WIDGET(browser->view));
      } else {
        browser->muted_before_hide = webkit_web_view_get_is_muted(browser->view);
        webkit_web_view_set_is_muted(browser->view, TRUE);
        browser_javascript(browser, "document.querySelectorAll('video,audio').forEach(v=>v.pause());");
        gtk_widget_hide(GTK_WIDGET(browser->view));
        if (self->flutter_view != nullptr) gtk_widget_grab_focus(GTK_WIDGET(self->flutter_view));
      }
    }
  } else if (g_strcmp0(method, "pointer") == 0) {
    const double x = std::max(0.0, std::min(1.0, browser_number(args, "fx")));
    const double y = std::max(0.0, std::min(1.0, browser_number(args, "fy")));
    browser_pointer_event(browser, x, y, GDK_MOTION_NOTIFY);
    gchar x_text[G_ASCII_DTOSTR_BUF_SIZE], y_text[G_ASCII_DTOSTR_BUF_SIZE];
    g_ascii_dtostr(x_text, sizeof(x_text), x);
    g_ascii_dtostr(y_text, sizeof(y_text), y);
    g_autofree gchar* script = g_strdup_printf(
        "(()=>{let c=document.getElementById('__telefon_tv_cursor');"
        "if(!c){c=document.createElement('div');c.id='__telefon_tv_cursor';"
        "c.style.cssText='position:fixed;width:18px;height:18px;border:3px solid white;"
        "border-radius:50%%;background:rgba(55,105,255,.7);box-shadow:0 1px 5px #000;"
        "z-index:2147483647;pointer-events:none;transform:translate(-50%%,-50%%)';"
        "document.documentElement.appendChild(c)}"
        "c.style.left=(%s*innerWidth)+'px';c.style.top=(%s*innerHeight)+'px';})()", x_text, y_text);
    browser_javascript(browser, script);
  } else if (g_strcmp0(method, "click") == 0) {
    gtk_widget_grab_focus(GTK_WIDGET(browser->view));
    const double x = browser_number(args, "fx");
    const double y = browser_number(args, "fy");
    browser_pointer_event(browser, x, y, GDK_MOTION_NOTIFY);
    browser_pointer_event(browser, x, y, GDK_BUTTON_PRESS);
    browser_pointer_event(browser, x, y, GDK_BUTTON_RELEASE);
  } else if (g_strcmp0(method, "sendKey") == 0) {
    browser_send_key(browser, browser_string(args, "key"));
  } else if (g_strcmp0(method, "typeText") == 0) {
    std::string text = javascript_string(browser_string(args, "text"));
    std::string script = "(()=>{const e=document.activeElement,t=" + text +
      ";if(!e)return;if(e.isContentEditable){document.execCommand('insertText',false,t);return;}"
      "if(e.tagName==='INPUT'||e.tagName==='TEXTAREA'){const s=e.selectionStart??e.value.length,"
      "n=e.selectionEnd??s;e.setRangeText(t,s,n,'end');"
      "e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:t}));}})()";
    browser_javascript(browser, script.c_str());
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  if (response == nullptr) response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  fl_method_call_respond(call, response, nullptr);
}


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
        "z3wax TV ochiq");
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
  // Ilova ochiq ekan ekran o‘chmasin va kompyuter uxlamasin (fon rejimida ham).
  set_awake(self, true);
  if (self->background && !tv_connected) {
    gtk_widget_hide(GTK_WIDGET(window));
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

// Dart bilan aloqa: televizor ekranining joyi (Chrome’ni o‘sha ekranda
// ochish uchun) va Chrome yopilgach oynani yana oldinga chiqarish.
static void native_method_cb(FlMethodChannel* channel, FlMethodCall* call,
                             gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "tvGeometry") == 0 && self->window != nullptr) {
    GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(self->window));
    GdkMonitor* m = gdk_display_get_monitor(display, pick_monitor(display));
    GdkRectangle a = {0, 0, 0, 0};
    if (m != nullptr) gdk_monitor_get_geometry(m, &a);
    g_autoptr(FlValue) list = fl_value_new_list();
    fl_value_append_take(list, fl_value_new_int(a.x));
    fl_value_append_take(list, fl_value_new_int(a.y));
    fl_value_append_take(list, fl_value_new_int(a.width));
    fl_value_append_take(list, fl_value_new_int(a.height));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
  } else if (g_strcmp0(method, "present") == 0 && self->window != nullptr) {
    gtk_window_present(self->window);
    g_autoptr(FlValue) ok = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(ok));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

static void window_destroyed_cb(MyApplication* self, GtkWidget* window) {
  g_signal_handlers_disconnect_by_data(gtk_widget_get_display(window), self);
  if (self->browsers != nullptr) g_hash_table_remove_all(self->browsers);
  self->overlay = nullptr;
  self->flutter_view = nullptr;
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
    gtk_header_bar_set_title(header_bar, "z3wax TV");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "z3wax TV");
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
  self->flutter_view = view;
  self->overlay = GTK_OVERLAY(gtk_overlay_new());
  gtk_container_add(GTK_CONTAINER(self->overlay), GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(self->overlay));
  gtk_widget_show(GTK_WIDGET(self->overlay));
  g_signal_connect(self->overlay, "get-child-position", G_CALLBACK(browser_position_cb), self);

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "telefon_tv/native", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, native_method_cb,
                                            self, nullptr);

  self->browser_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "telefon_tv/browser", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->browser_channel, browser_method_cb, self, nullptr);

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
  if (self->browsers != nullptr) g_hash_table_remove_all(self->browsers);
  g_clear_pointer(&self->browsers, g_hash_table_unref);
  g_clear_object(&self->browser_channel);
  g_clear_object(&self->channel);
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
  self->channel = nullptr;
  self->browser_channel = nullptr;
  self->overlay = nullptr;
  self->flutter_view = nullptr;
  self->browsers = g_hash_table_new_full(g_int64_hash, g_int64_equal, g_free, browser_view_destroy);
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
