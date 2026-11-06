import AVFoundation
import Flutter
import ImageIO
import Speech
import UIKit
import UniformTypeIdentifiers

/// Telefon ekrani — pult, televizor (HDMI adapter yoki AirPlay) — Smart TV.
///
/// Tashqi ekran ulanganda ikkinchi Flutter dvigateli `tvMain` bilan ishga
/// tushadi va o‘sha ekrandagi alohida oynada chiziladi.
@main
@objc class AppDelegate: FlutterAppDelegate {
  private var tvEngine: FlutterEngine?
  private var tvWindow: UIWindow?
  private var phoneChannel: FlutterMethodChannel?
  private var tvChannel: FlutterMethodChannel?
  private var usb: UsbExporter?
  private var voice: VoiceInput?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      phoneChannel = bindChannel(controller.binaryMessenger)
      usb = UsbExporter(messenger: controller.binaryMessenger, presenter: controller)
      voice = VoiceInput(messenger: controller.binaryMessenger)
    }
    application.isIdleTimerDisabled = true
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(screenConnected(_:)),
      name: UIScreen.didConnectNotification, object: nil)
    center.addObserver(
      self, selector: #selector(screenDisconnected(_:)),
      name: UIScreen.didDisconnectNotification, object: nil)
    if let screen = UIScreen.screens.dropFirst().first {
      showOnTv(screen)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func bindChannel(_ messenger: FlutterBinaryMessenger) -> FlutterMethodChannel {
    let channel = FlutterMethodChannel(name: "telefon_tv/native", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "externalDisplay":
        result(self?.tvWindow != nil)
      case "openUrl":
        guard let args = call.arguments as? [String: Any],
          let text = args["url"] as? String,
          let url = URL(string: text)
        else {
          result(false)
          return
        }
        UIApplication.shared.open(url, options: [:]) { ok in result(ok) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    return channel
  }

  @objc private func screenConnected(_ note: Notification) {
    if let screen = note.object as? UIScreen { showOnTv(screen) }
  }

  @objc private func screenDisconnected(_ note: Notification) {
    guard let screen = note.object as? UIScreen, tvWindow?.screen == screen else { return }
    hideTv()
  }

  private func showOnTv(_ screen: UIScreen) {
    guard tvWindow == nil else { return }
    let engine: FlutterEngine
    if let existing = tvEngine {
      engine = existing
    } else {
      engine = FlutterEngine(name: "tv", project: nil, allowHeadlessExecution: true)
      engine.run(withEntrypoint: "tvMain")
      GeneratedPluginRegistrant.register(with: engine)
      tvChannel = bindChannel(engine.binaryMessenger)
      tvEngine = engine
    }
    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    let window = UIWindow(frame: screen.bounds)
    window.screen = screen
    window.rootViewController = controller
    window.isHidden = false
    tvWindow = window
    phoneChannel?.invokeMethod("externalDisplay", arguments: true)
  }

  private func hideTv() {
    tvWindow?.isHidden = true
    tvWindow?.rootViewController = nil
    tvWindow = nil
    // Televizor uzildi: TV dvigateli (va uning pult serveri) to‘xtaydi,
    // telefon ekranidagi Smart TV o‘z serverini ochadi.
    tvEngine?.viewController = nil
    tvEngine?.destroyContext()
    tvEngine = nil
    tvChannel = nil
    phoneChannel?.invokeMethod("externalDisplay", arguments: false)
  }
}

/// “USB orqali televizorga”: iPhone’ga ulangan fleshkaga fayllarni oddiy
/// televizor (Yasin, Artel, Samsung…) o‘qiy oladigan shaklda yozadi.
///
/// * Video H.264 bo‘lmasa, MP4 bo‘lmasa yoki televizor uchun juda katta
///   bo‘lsa (Yasin LED-32E58TS uchun 720p dan katta) → H.264 MP4.
/// * HEIC / WEBP yoki juda katta rasm → JPEG.
final class UsbExporter: NSObject, UIDocumentPickerDelegate {
  private let channel: FlutterMethodChannel
  private weak var presenter: UIViewController?
  private var pending: FlutterResult?
  private var target: URL?

  init(messenger: FlutterBinaryMessenger, presenter: UIViewController) {
    channel = FlutterMethodChannel(name: "telefon_tv/usb", binaryMessenger: messenger)
    self.presenter = presenter
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "pickTarget":
        self.pick(result)
      case "copy":
        let args = call.arguments as? [String: Any] ?? [:]
        let root = args["root"] as? String ?? "TELEFON_TV"
        let files = args["files"] as? [[String: Any]] ?? []
        let maxShort = args["maxVideoShort"] as? Int ?? 1080
        let maxImage = args["maxImageSide"] as? Int ?? 3840
        self.copy(
          root: root, files: files, maxShort: maxShort, maxImage: maxImage, result: result)
      case "apkPath":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func pick(_ result: @escaping FlutterResult) {
    pending?(nil)
    pending = result
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
    } else {
      picker = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open)
    }
    picker.delegate = self
    picker.allowsMultipleSelection = false
    presenter?.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    target = urls.first
    if let url = target {
      pending?(["id": url.absoluteString, "name": url.lastPathComponent])
    } else {
      pending?(nil)
    }
    pending = nil
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pending?(nil)
    pending = nil
  }

  private func progress(_ done: Int, _ total: Int, _ name: String, _ converting: Bool) {
    DispatchQueue.main.async {
      self.channel.invokeMethod(
        "progress",
        arguments: ["done": done, "total": total, "name": name, "converting": converting])
    }
  }

  private func copy(
    root: String, files: [[String: Any]], maxShort: Int, maxImage: Int,
    result: @escaping FlutterResult
  ) {
    guard let target = target else {
      result(FlutterError(code: "no_target", message: "Avval fleshkani tanlang", details: nil))
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let access = target.startAccessingSecurityScopedResource()
      defer { if access { target.stopAccessingSecurityScopedResource() } }
      let fm = FileManager.default
      var copied = 0
      var converted = 0
      var failed: [String] = []
      let base = target.appendingPathComponent(root, isDirectory: true)
      for (i, f) in files.enumerated() {
        guard let path = f["path"] as? String else { continue }
        var name = f["name"] as? String ?? URL(fileURLWithPath: path).lastPathComponent
        let folder = f["folder"] as? String ?? ""
        do {
          let dir = folder.isEmpty ? base : base.appendingPathComponent(folder, isDirectory: true)
          try fm.createDirectory(at: dir, withIntermediateDirectories: true)
          let src = URL(fileURLWithPath: path)
          let ext = src.pathExtension.lowercased()
          var temp: URL?
          if Self.imageExt.contains(ext) {
            if Self.imageNeedsJpeg(src, maxSide: maxImage) {
              self.progress(i, files.count, name, true)
              temp = try Self.toJpeg(src, maxSide: maxImage)
              name = (name as NSString).deletingPathExtension + ".jpg"
            } else {
              self.progress(i, files.count, name, false)
            }
          } else if let preset = Self.videoPreset(src, maxShort: maxShort) {
            self.progress(i, files.count, name, true)
            if let out = try? Self.exportMp4(src, preset: preset) {
              temp = out
              name = (name as NSString).deletingPathExtension + ".mp4"
            } else if preset != AVAssetExportPresetPassthrough {
              throw NSError(domain: "usb", code: 4)
            }  // .mov → .mp4 o‘ramasi bo‘lmasa — asl fayl yoziladi
          } else {
            self.progress(i, files.count, name, false)
          }
          let dest = dir.appendingPathComponent(name)
          if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
          try fm.copyItem(at: temp ?? src, to: dest)
          if let t = temp {
            try? fm.removeItem(at: t)
            converted += 1
          }
          copied += 1
        } catch {
          failed.append(name)
        }
      }
      self.progress(files.count, files.count, "", false)
      DispatchQueue.main.async {
        result(["copied": copied, "converted": converted, "failed": failed])
      }
    }
  }

  private static let imageExt: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "bmp"]

  /// H.264 bo‘lmasa yoki katta bo‘lsa → H.264 (720p yoki 1080p gacha);
  /// H.264 .mov → .mp4 (sifat o‘zgarmaydi); mos bo‘lsa — nil.
  private static func videoPreset(_ url: URL, maxShort: Int) -> String? {
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .video).first else { return nil }
    let isH264 = track.formatDescriptions.contains { desc in
      CMFormatDescriptionGetMediaSubType(desc as! CMFormatDescription) == kCMVideoCodecType_H264
    }
    let size = track.naturalSize.applying(track.preferredTransform)
    let short = min(abs(size.width), abs(size.height))
    if !isH264 || short > CGFloat(maxShort) + 1 {
      return maxShort <= 720 ? AVAssetExportPreset1280x720 : AVAssetExportPreset1920x1080
    }
    let ext = url.pathExtension.lowercased()
    return ext == "mp4" || ext == "m4v" ? nil : AVAssetExportPresetPassthrough
  }

  private static func imageNeedsJpeg(_ url: URL, maxSide: Int) -> Bool {
    let ext = url.pathExtension.lowercased()
    if ext == "heic" || ext == "heif" || ext == "webp" { return true }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
      let w = (props[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue,
      let h = (props[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue
    else { return false }
    return max(w, h) > Double(maxSide)
  }

  private static func exportMp4(_ src: URL, preset: String) throws -> URL {
    let out = FileManager.default.temporaryDirectory
      .appendingPathComponent("usb_\(UUID().uuidString).mp4")
    guard let session = AVAssetExportSession(asset: AVURLAsset(url: src), presetName: preset) else {
      throw NSError(domain: "usb", code: 1)
    }
    session.outputURL = out
    session.outputFileType = .mp4
    session.shouldOptimizeForNetworkUse = true
    let done = DispatchSemaphore(value: 0)
    session.exportAsynchronously { done.signal() }
    done.wait()
    guard session.status == .completed else {
      throw session.error ?? NSError(domain: "usb", code: 2)
    }
    return out
  }

  /// JPEG, uzun tomoni [maxSide] gacha (burilish hisobga olinadi).
  private static func toJpeg(_ src: URL, maxSide: Int) throws -> URL {
    guard let image = UIImage(contentsOfFile: src.path) else {
      throw NSError(domain: "usb", code: 3)
    }
    let longest = max(image.size.width, image.size.height)
    let k = min(1, CGFloat(maxSide) / max(longest, 1))
    let target = CGSize(width: floor(image.size.width * k), height: floor(image.size.height * k))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let data = UIGraphicsImageRenderer(size: target, format: format).jpegData(
      withCompressionQuality: 0.9
    ) { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
    let out = FileManager.default.temporaryDirectory
      .appendingPathComponent("usb_\(UUID().uuidString).jpg")
    try data.write(to: out)
    return out
  }
}

/// Pultdagi mikrofon: iPhone’ning o‘z ovoz tanish dvigateli (Speech).
/// Eshitilayotgan so‘zlar `partial`, tayyor gap `final` bilan yuboriladi;
/// 1,6 soniya jimlikdan keyin o‘zi tugaydi.
final class VoiceInput: NSObject {
  private let channel: FlutterMethodChannel
  private let engine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var recognizer: SFSpeechRecognizer?
  private var silence: DispatchWorkItem?
  private var finished = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "telefon_tv/voice", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "available":
        result(SFSpeechRecognizer() != nil)
      case "start":
        let args = call.arguments as? [String: Any]
        let locales = args?["locales"] as? [String] ?? ["uz-UZ", "ru-RU", "en-US"]
        self.authorize { ok in
          if ok { self.start(locales) } else { self.send("error", "permission") }
        }
        result(true)
      case "stop":
        self.stop()
        result(true)
      case "cancel":
        self.cancel()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func send(_ method: String, _ value: String) {
    DispatchQueue.main.async { self.channel.invokeMethod(method, arguments: value) }
  }

  private func authorize(_ done: @escaping (Bool) -> Void) {
    SFSpeechRecognizer.requestAuthorization { status in
      guard status == .authorized else {
        DispatchQueue.main.async { done(false) }
        return
      }
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        DispatchQueue.main.async { done(granted) }
      }
    }
  }

  private func start(_ locales: [String]) {
    cancel()
    var chosen: SFSpeechRecognizer?
    var chosenId = ""
    for id in locales {
      if let r = SFSpeechRecognizer(locale: Locale(identifier: id)), r.isAvailable {
        chosen = r
        chosenId = id
        break
      }
    }
    guard let recognizer = chosen else {
      send("error", "language")
      return
    }
    self.recognizer = recognizer
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      send("error", "busy")
      return
    }
    let req = SFSpeechAudioBufferRecognitionRequest()
    req.shouldReportPartialResults = true
    request = req
    let input = engine.inputNode
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
      req.append(buffer)
    }
    engine.prepare()
    do {
      try engine.start()
    } catch {
      send("error", "busy")
      return
    }
    finished = false
    send("ready", chosenId)
    scheduleSilence(after: 6)
    task = recognizer.recognitionTask(with: req) { [weak self] result, error in
      guard let self = self, !self.finished else { return }
      if let result = result {
        let text = result.bestTranscription.formattedString
        if result.isFinal {
          self.finished = true
          self.send("final", text)
          self.teardown()
        } else {
          self.send("partial", text)
          self.scheduleSilence(after: 1.6)
        }
      } else if error != nil {
        self.finished = true
        self.send("error", "nomatch")
        self.teardown()
      }
    }
  }

  /// Jimlik: gapirib bo‘lingan deb hisoblaymiz.
  private func scheduleSilence(after seconds: Double) {
    silence?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.stop() }
    silence = work
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
  }

  func stop() {
    silence?.cancel()
    if engine.isRunning {
      engine.stop()
      engine.inputNode.removeTap(onBus: 0)
    }
    request?.endAudio()
  }

  func cancel() {
    silence?.cancel()
    task?.cancel()
    task = nil
    teardown()
  }

  private func teardown() {
    silence?.cancel()
    if engine.isRunning { engine.stop() }
    engine.inputNode.removeTap(onBus: 0)
    request = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
