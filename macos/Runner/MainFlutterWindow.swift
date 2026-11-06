import Cocoa
import FlutterMacOS

/// Telefon TV oynasi.
///
/// * Televizor (HDMI yoki USB-C → HDMI) ulangan bo‘lsa — o‘sha ekranni
///   to‘liq, chegarasiz egallaydi; Mac’ning o‘z ekrani bo‘sh qoladi, ishlashda
///   davom etish mumkin. Ulangan / uzilgan zahoti o‘zi ko‘chadi.
/// * Televizor yo‘q — oddiy oyna.
/// * `--background` — televizor ulanmaguncha yashirin (Dock’da ham yo‘q),
///   pult serveri ishlab turadi.
/// * Televizorda ko‘rsatayotganda ekran o‘chmaydi, Mac uxlamaydi.
/// * Televizorni qo‘lda tanlash: `TELEFON_TV_SCREEN=<raqam>`.
class MainFlutterWindow: NSWindow {
  private let background = CommandLine.arguments.contains("--background")
  private var onTv = false
  private var awake: NSObjectProtocol?

  // Chegarasiz oyna ham klaviatura / pult tugmalarini qabul qilsin.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.title = "Telefon TV"
    self.backgroundColor = .black

    RegisterGeneratedPlugins(registry: flutterViewController)

    NotificationCenter.default.addObserver(
      self, selector: #selector(screensChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)

    super.awakeFromNib()
    DispatchQueue.main.async { [weak self] in self?.place() }
  }

  @objc private func screensChanged() {
    place()
  }

  private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
    return CGDirectDisplayID(number.uint32Value)
  }

  /// Televizor: qo‘lda tanlangan ekran yoki Mac’ga o‘rnatilmagan (tashqi)
  /// ekranlardan jismonan eng kattasi. Mac mini’ga faqat televizor ulangan
  /// bo‘lsa — o‘sha.
  private func tvScreen() -> NSScreen? {
    let screens = NSScreen.screens
    if let raw = ProcessInfo.processInfo.environment["TELEFON_TV_SCREEN"],
      let index = Int(raw), screens.indices.contains(index)
    {
      return screens[index]
    }
    let external = screens.filter { screen in
      guard let id = Self.displayID(screen) else { return false }
      return CGDisplayIsBuiltin(id) == 0
    }
    return external.max { a, b in
      let wa = Self.displayID(a).map { CGDisplayScreenSize($0).width } ?? 0
      let wb = Self.displayID(b).map { CGDisplayScreenSize($0).width } ?? 0
      return wa < wb
    }
  }

  private func place() {
    if let tv = tvScreen() {
      showOnTv(tv)
    } else {
      showWithoutTv()
    }
  }

  private func showOnTv(_ tv: NSScreen) {
    let firstTime = !onTv
    onTv = true
    NSApp.setActivationPolicy(background ? .accessory : .regular)
    styleMask = [.borderless]
    // Televizor ekranidagi menyu satri ustida turadi.
    level = .statusBar
    collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
    setFrame(tv.frame, display: true)
    orderFrontRegardless()
    if firstTime {
      NSApp.activate(ignoringOtherApps: true)
      makeKey()
    }
    setAwake(true)
  }

  private func showWithoutTv() {
    let wasOnTv = onTv
    onTv = false
    setAwake(false)
    if background {
      orderOut(nil)
      NSApp.setActivationPolicy(.accessory)
      return
    }
    NSApp.setActivationPolicy(.regular)
    styleMask = [.titled, .closable, .miniaturizable, .resizable]
    level = .normal
    collectionBehavior = []
    title = "Telefon TV"
    if wasOnTv || !isVisible, let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
      let size = NSSize(width: min(1280, area.width), height: min(720, area.height))
      setFrame(
        NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
               width: size.width, height: size.height),
        display: true)
    }
    makeKeyAndOrderFront(nil)
  }

  private func setAwake(_ on: Bool) {
    if on, awake == nil {
      awake = ProcessInfo.processInfo.beginActivity(
        options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled],
        reason: "Telefon TV televizorda ko‘rsatmoqda")
    } else if !on, let activity = awake {
      ProcessInfo.processInfo.endActivity(activity)
      awake = nil
    }
  }
}
