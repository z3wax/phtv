import Cocoa
import CoreAudio
import FlutterMacOS
import IOKit.pwr_mgt
import WebKit

/// Telefon TV oynasi.
///
/// * Televizor (HDMI yoki USB-C → HDMI) ulangan bo‘lsa — o‘sha ekranni
///   to‘liq, chegarasiz egallaydi; Mac’ning o‘z ekrani bo‘sh qoladi, ishlashda
///   davom etish mumkin. Ulangan / uzilgan zahoti o‘zi ko‘chadi.
/// * Televizor yo‘q — oddiy oyna.
/// * `--background` — televizor ulanmaguncha yashirin (Dock’da ham yo‘q),
///   pult serveri ishlab turadi.
/// * Ilova ochiq ekan ekran o‘chmaydi, qulflanmaydi, Mac uxlamaydi.
/// * Televizorni qo‘lda tanlash: `TELEFON_TV_SCREEN=<raqam>`.
/// * Televizorga o‘tganda ovoz ham televizordan chiqadi (HDMI / DisplayPort),
///   televizordan chiqqanda — avvalgi chiqish. O‘chirish:
///   `TELEFON_TV_KEEP_AUDIO=1`.
class MainFlutterWindow: NSWindow {
  private let background = CommandLine.arguments.contains("--background")
  private var onTv = false
  private var awake: NSObjectProtocol?
  private var activityTimer: Timer?
  private var idleAssertion: IOPMAssertionID = 0
  private var channel: FlutterMethodChannel?

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
    bindChannel(flutterViewController.engine.binaryMessenger)

    NotificationCenter.default.addObserver(
      self, selector: #selector(screensChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(willTerminate),
      name: NSApplication.willTerminateNotification, object: nil)

    super.awakeFromNib()
    setAwake(true)
    DispatchQueue.main.async { [weak self] in self?.place() }
  }

  /// YouTube va brauzer: havolani ochish, ichki brauzerga pult tugmalari.
  private func bindChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "telefon_tv/native", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "openUrl":
        guard let text = args?["url"] as? String, let url = URL(string: text) else {
          result(false)
          return
        }
        result(NSWorkspace.shared.open(url))
      case "sendKey":
        result(self?.sendKey(args?["key"] as? String ?? "") ?? false)
      case "externalDisplay":
        result(false)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  private func findWebView(_ view: NSView) -> WKWebView? {
    if let web = view as? WKWebView { return web }
    for sub in view.subviews {
      if let web = findWebView(sub) { return web }
    }
    return nil
  }

  /// Pult tugmasini ichki brauzerga haqiqiy klaviatura tugmasi sifatida
  /// yuboradi (YouTube TV ko‘rinishi ↑↓←→, Enter, Esc bilan boshqariladi).
  private func sendKey(_ key: String) -> Bool {
    guard let content = contentView, let web = findWebView(content) else { return false }
    let table: [String: (UInt16, Int)] = [
      "up": (126, NSUpArrowFunctionKey), "down": (125, NSDownArrowFunctionKey),
      "left": (123, NSLeftArrowFunctionKey), "right": (124, NSRightArrowFunctionKey),
      "enter": (36, 13), "escape": (53, 27), "space": (49, 32), "backspace": (51, 8),
    ]
    guard let entry = table[key], let u = UnicodeScalar(UInt32(entry.1)) else { return false }
    let code = entry.0
    let chars = String(Character(u))
    makeFirstResponder(web)
    for type in [NSEvent.EventType.keyDown, .keyUp] {
      guard let event = NSEvent.keyEvent(
        with: type, location: .zero, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber,
        context: nil, characters: chars, charactersIgnoringModifiers: chars,
        isARepeat: false, keyCode: code)
      else { continue }
      if type == .keyDown { web.keyDown(with: event) } else { web.keyUp(with: event) }
    }
    return true
  }

  @objc private func screensChanged() {
    place()
  }

  @objc private func willTerminate() {
    TvAudio.restore()
  }

  /// Ovozni televizorga o‘tkazadi. Televizor ovoz qurilmasi ekrandan
  /// biroz keyin paydo bo‘lishi mumkin — bir necha marta urinadi.
  private func routeAudio(to tv: NSScreen, attempt: Int = 0) {
    guard onTv else { return }
    if TvAudio.route(to: tv) || attempt >= 3 { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
      guard let self = self, self.onTv, let screen = self.tvScreen() else { return }
      self.routeAudio(to: screen, attempt: attempt + 1)
    }
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
      routeAudio(to: tv)
    }
  }

  private func showWithoutTv() {
    let wasOnTv = onTv
    onTv = false
    if wasOnTv { TvAudio.restore() }
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

  /// Ekran o‘chmasin, ekran saqlovchi va qulf chiqmasin, Mac uxlamasin —
  /// ilova yopilguncha (video ijro etilmayotganda ham).
  private func setAwake(_ on: Bool) {
    if on, awake == nil {
      awake = ProcessInfo.processInfo.beginActivity(
        options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .userInitiated],
        reason: "Telefon TV ochiq")
      declareActivity()
      activityTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
        self?.declareActivity()
      }
    } else if !on, let activity = awake {
      ProcessInfo.processInfo.endActivity(activity)
      awake = nil
      activityTimer?.invalidate()
      activityTimer = nil
    }
  }

  /// Foydalanuvchi faol deb hisoblanadi: ekran saqlovchi va avtomatik qulf
  /// ishga tushmaydi.
  private func declareActivity() {
    IOPMAssertionDeclareUserActivity(
      "Telefon TV" as CFString, kIOPMUserActiveLocal, &idleAssertion)
  }
}

/// Televizor ovozi: ilova televizor ekraniga chiqqanda televizorning HDMI /
/// DisplayPort ovoz qurilmasini tizimning asosiy chiqishi qiladi (macOS buni
/// o‘zi qilmaydi — ovoz Mac dinamigida qoladi), televizordan chiqqanda yoki
/// ilova yopilganda avvalgisini qaytaradi.
private enum TvAudio {
  private static var previous: AudioDeviceID?
  private static var current: AudioDeviceID?
  private static let system = AudioObjectID(kAudioObjectSystemObject)

  private static func address(
    _ selector: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> AudioObjectPropertyAddress {
    // mElement 0 — “main” (macOS 10.15 da ham).
    return AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: 0)
  }

  private static func devices() -> [AudioDeviceID] {
    var addr = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0
    else { return [] }
    var ids = [AudioDeviceID](
      repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr
    else { return [] }
    return ids
  }

  private static func transport(_ id: AudioDeviceID) -> UInt32 {
    var addr = address(kAudioDevicePropertyTransportType)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr ? value : 0
  }

  private static func hasOutput(_ id: AudioDeviceID) -> Bool {
    var addr = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
  }

  private static func name(_ id: AudioDeviceID) -> String {
    var addr = address(kAudioObjectPropertyName)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr,
      let text = value?.takeRetainedValue()
    else { return "" }
    return text as String
  }

  private static func defaultOutput() -> AudioDeviceID? {
    var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &id) == noErr, id != 0
    else { return nil }
    return id
  }

  private static func setDefaultOutput(_ id: AudioDeviceID) -> Bool {
    var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
    var value = id
    let size = UInt32(MemoryLayout<AudioDeviceID>.size)
    return AudioObjectSetPropertyData(system, &addr, 0, nil, size, &value) == noErr
  }

  /// Televizor ekranining ovoz qurilmasi: nomi ekran nomiga mos HDMI /
  /// DisplayPort chiqishi, bo‘lmasa — birinchi HDMI / DisplayPort chiqishi.
  private static func device(for screen: NSScreen) -> AudioDeviceID? {
    let outputs = devices().filter { id in
      let kind = transport(id)
      return (kind == kAudioDeviceTransportTypeHDMI
        || kind == kAudioDeviceTransportTypeDisplayPort) && hasOutput(id)
    }
    let screenName = screen.localizedName.lowercased()
    if !screenName.isEmpty,
      let match = outputs.first(where: { id in
        let deviceName = name(id).lowercased()
        return !deviceName.isEmpty
          && (deviceName.contains(screenName) || screenName.contains(deviceName))
      })
    {
      return match
    }
    return outputs.first
  }

  /// Ovozni televizorga o‘tkazadi; televizor ovoz qurilmasi topilmasa — false.
  @discardableResult
  static func route(to screen: NSScreen) -> Bool {
    if ProcessInfo.processInfo.environment["TELEFON_TV_KEEP_AUDIO"] != nil { return true }
    guard let tv = device(for: screen) else { return false }
    let now = defaultOutput()
    if now == tv {
      current = tv
      return true
    }
    guard setDefaultOutput(tv) else { return false }
    if previous == nil { previous = now }
    current = tv
    return true
  }

  /// Avvalgi chiqishni qaytaradi — agar foydalanuvchi o‘zi boshqasini
  /// tanlamagan bo‘lsa va avvalgi qurilma hali ulangan bo‘lsa.
  static func restore() {
    defer {
      previous = nil
      current = nil
    }
    guard let before = previous, let tv = current, defaultOutput() == tv,
      devices().contains(before)
    else { return }
    _ = setDefaultOutput(before)
  }
}
