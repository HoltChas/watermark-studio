import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let videoFileDropped = Notification.Name("WatermarkStudioVideoFileDropped")
    static let videoFileDropTargetChanged = Notification.Name("WatermarkStudioVideoFileDropTargetChanged")
}

final class DropHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes([
            .fileURL,
            .URL,
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard firstVideoURL(from: sender.draggingPasteboard) != nil else { return [] }
        NotificationCenter.default.post(name: .videoFileDropTargetChanged, object: true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        NotificationCenter.default.post(name: .videoFileDropTargetChanged, object: false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        NotificationCenter.default.post(name: .videoFileDropTargetChanged, object: false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        NotificationCenter.default.post(name: .videoFileDropTargetChanged, object: false)
        guard let url = firstVideoURL(from: sender.draggingPasteboard) else { return false }
        NotificationCenter.default.post(name: .videoFileDropped, object: url)
        return true
    }

    private func firstVideoURL(from pasteboard: NSPasteboard) -> URL? {
        let allowedExtensions = ["mp4", "mov", "m4v"]

        if let urlString = pasteboard.string(forType: .fileURL),
           let url = URL(string: urlString),
           allowedExtensions.contains(url.pathExtension.lowercased()) {
            return url
        }

        if let urlString = pasteboard.string(forType: .URL),
           let url = URL(string: urlString),
           allowedExtensions.contains(url.pathExtension.lowercased()) {
            return url
        }

        let filenameType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let files = pasteboard.propertyList(forType: filenameType) as? [String] {
            return files
                .map { URL(fileURLWithPath: $0) }
                .first { allowedExtensions.contains($0.pathExtension.lowercased()) }
        }

        return nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let content = ContentView()
            .frame(minWidth: 1120, minHeight: 760)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Watermark Studio"
        window.center()
        window.contentView = DropHostingView(rootView: content)
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct WatermarkStudioApp {
    @MainActor
    private static let appDelegate = AppDelegate()

    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

enum CleanupPreset: String, CaseIterable, Identifiable {
    case fast = "Fast"
    case balanced = "Balanced"
    case quality = "Quality"

    var id: String { rawValue }

    var segmentFrames: Int {
        switch self {
        case .fast: 72
        case .balanced: 48
        case .quality: 36
        }
    }

    var raftIter: Int {
        switch self {
        case .fast: 6
        case .balanced: 10
        case .quality: 14
        }
    }

    var refStride: Int {
        switch self {
        case .fast: 15
        case .balanced: 10
        case .quality: 8
        }
    }

    var subvideoLength: Int {
        switch self {
        case .fast: 12
        case .balanced: 12
        case .quality: 10
        }
    }

    var processScale: Double {
        switch self {
        case .fast: 0.5
        case .balanced: 1.0
        case .quality: 1.0
        }
    }

    var recommendedRoiPadding: Int {
        switch self {
        case .fast: 128
        case .balanced: 256
        case .quality: 0
        }
    }

    var description: String {
        switch self {
        case .fast:
            "Crops to the marked area, half-resolution repair, then composites back."
        case .balanced:
            "The tested Axolotl production setting."
        case .quality:
            "Slower, more conservative temporal repair."
        }
    }
}

enum MarkMode: String, CaseIterable, Identifiable {
    case box = "Box"
    case draw = "Draw"

    var id: String { rawValue }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case zh = "中文"
    case en = "EN"

    var id: String { rawValue }

    func text(_ english: String, _ chinese: String) -> String {
        switch self {
        case .zh: chinese
        case .en: english
        }
    }
}

struct ContentView: View {
    private enum SettingsKey {
        static let pythonPath = "watermarkStudio.pythonPath"
        static let propainterPath = "watermarkStudio.propainterPath"
    }

    @State private var appLanguage: AppLanguage = .zh
    @State private var videoURL: URL?
    @State private var previewImage: NSImage?
    @State private var videoSize: CGSize = CGSize(width: 720, height: 1280)
    @State private var selection = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
    @State private var markMode: MarkMode = .box
    @State private var drawnPoints: [CGPoint] = []
    @State private var isDrawClosed = false
    @State private var zoomScale = 1.0
    @State private var pythonPath = UserDefaults.standard.string(forKey: SettingsKey.pythonPath) ?? "python3"
    @State private var propainterPath = UserDefaults.standard.string(forKey: SettingsKey.propainterPath) ?? ""
    @State private var outputPath = ""
    @State private var autoOutputName = true
    @State private var expandPixels = 3.0
    @State private var cleanupPreset: CleanupPreset = .balanced
    @State private var roiPadding = 256.0
    @State private var logText = "Ready"
    @State private var isRunning = false
    @State private var isDropTarget = false
    @State private var hasMarked = false
    @State private var showMaskPreview = false
    @State private var cleanupStartedAt: Date?
    @State private var elapsedSeconds = 0
    @State private var lastExitCode: Int?
    @State private var completedOutputPath = ""
    @State private var completedElapsedSeconds: Int?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            Sidebar(language: appLanguage, videoURL: videoURL, hasMarked: hasMarked, showMaskPreview: showMaskPreview, isRunning: isRunning, lastExitCode: lastExitCode)
        } detail: {
            HStack(spacing: 0) {
                previewPane
                Divider()
                inspector
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: openVideo) {
                    Label(t("Open Video", "打开视频"), systemImage: "folder")
                }
                Button(action: runCleanup) {
                    Label(isRunning ? t("Running", "处理中") : t("Run Cleanup", "开始处理"), systemImage: "play.circle.fill")
                }
                .disabled(videoURL == nil || isRunning)
                Picker("", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.rawValue).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 96)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .videoFileDropped)) { notification in
            guard let url = notification.object as? URL else { return }
            setVideoURL(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .videoFileDropTargetChanged)) { notification in
            isDropTarget = (notification.object as? Bool) ?? false
        }
        .onReceive(timer) { _ in
            guard isRunning, let cleanupStartedAt else { return }
            elapsedSeconds = max(0, Int(Date().timeIntervalSince(cleanupStartedAt)))
        }
        .onChange(of: pythonPath) { _, value in
            UserDefaults.standard.set(value, forKey: SettingsKey.pythonPath)
        }
        .onChange(of: propainterPath) { _, value in
            UserDefaults.standard.set(value, forKey: SettingsKey.propainterPath)
        }
    }

    private var previewPane: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Watermark Studio")
                        .font(.system(size: 28, weight: .semibold))
                    Text(videoURL?.lastPathComponent ?? t("Open a video and drag the box over the watermark.", "打开视频，然后把标记框拖到水印上。"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                statusPill
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)

                if let previewImage {
                    GeometryReader { proxy in
                        CursorZoomScrollView(zoomScale: $zoomScale, baseSize: proxy.size, minZoom: 1, maxZoom: 4) {
                            MarkableVideoView(
                                image: previewImage,
                                selection: $selection,
                                markMode: markMode,
                                drawnPoints: $drawnPoints,
                                isDrawClosed: $isDrawClosed,
                                showMaskPreview: showMaskPreview,
                                expandPixels: expandPixels,
                                videoSize: videoSize
                            ) {
                                hasMarked = true
                            }
                        }
                    }
                    .padding(18)
                } else {
                    Button(action: openVideo) {
                        VStack(spacing: 12) {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 44))
                                .foregroundStyle(.teal)
                            Text("Open Video")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(t("The first frame appears here. Drag the selection box to cover the watermark.", "第一帧会显示在这里。拖动标记框盖住水印。"))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isDropTarget ? Color.teal : Color.clear, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .background(isDropTarget ? Color.teal.opacity(0.08) : Color.clear)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 22)

            ProgressTimeline(language: appLanguage, segmentFrames: cleanupPreset.segmentFrames, isRunning: isRunning, elapsedSeconds: elapsedSeconds, lastExitCode: lastExitCode)
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isRunning ? Color.orange : Color.teal)
                .frame(width: 8, height: 8)
            Text(isRunning ? t("Running", "处理中") : t("Ready", "就绪"))
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox(t("Mark", "标记")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker(t("Mode", "模式"), selection: $markMode) {
                            ForEach(MarkMode.allCases) { mode in
                                Text(markModeTitle(mode)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(videoURL == nil)
                        metricRow(t("Video", "视频"), "\(Int(videoSize.width)) x \(Int(videoSize.height))")
                        metricRow(markMode == .box ? t("Rect", "矩形") : t("Polygon", "多边形"), markMode == .box ? rectString : drawStatus)
                        SliderRow(title: t("Zoom", "缩放"), value: $zoomScale, range: 1...4, suffix: "x")
                        HStack(spacing: 8) {
                            ForEach([1.0, 2.0, 3.0], id: \.self) { scale in
                                Button("\(Int(scale))x") {
                                    zoomScale = scale
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        if markMode == .draw {
                            HStack(spacing: 8) {
                                Button {
                                    isDrawClosed = true
                                    showMaskPreview = true
                                    hasMarked = true
                                } label: {
                                    Label(t("Close Draw", "闭合手绘"), systemImage: "checkmark.seal")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.teal)
                                .disabled(drawnPoints.count < 3 || isDrawClosed)
                                Button {
                                    if !drawnPoints.isEmpty {
                                        drawnPoints.removeLast()
                                    }
                                    isDrawClosed = false
                                    hasMarked = drawnPoints.count >= 3
                                } label: {
                                    Label(t("Undo Point", "撤销点"), systemImage: "arrow.uturn.backward")
                                }
                                .buttonStyle(.bordered)
                                .disabled(drawnPoints.isEmpty)
                            }
                            Button {
                                drawnPoints.removeAll()
                                isDrawClosed = false
                                if markMode == .draw {
                                    hasMarked = false
                                }
                            } label: {
                                Label(t("Clear Draw", "清空手绘"), systemImage: "eraser")
                            }
                            .buttonStyle(.bordered)
                            .disabled(markMode != .draw || drawnPoints.isEmpty)
                        }
                        SliderRow(title: t("Mask Expand", "遮罩扩展"), value: $expandPixels, range: 0...24, suffix: "px")
                        Toggle(isOn: $showMaskPreview) {
                            Label(t("Preview Mask", "预览遮罩"), systemImage: showMaskPreview ? "eye.fill" : "eye")
                        }
                        .toggleStyle(.button)
                        .disabled(videoURL == nil)
                        InfoBlock(text: markHelpText)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox(t("Backend", "处理参数")) {
                    VStack(spacing: 10) {
                        Picker(t("Speed", "速度"), selection: $cleanupPreset) {
                            ForEach(CleanupPreset.allCases) { preset in
                                Text(presetTitle(preset)).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: cleanupPreset) { _, preset in
                            roiPadding = Double(preset.recommendedRoiPadding)
                        }
                        InfoBlock(text: presetDescription(cleanupPreset))
                        PathField(title: "Python", text: $pythonPath, canChooseDirectory: false)
                        PathField(title: "ProPainter", text: $propainterPath, canChooseDirectory: true)
                        metricRow(t("Segment Length", "分段长度"), "\(cleanupPreset.segmentFrames) \(t("frames", "帧"))")
                        metricRow(t("Process Scale", "处理分辨率"), "\(cleanupPreset.processScale.formatted(.number.precision(.fractionLength(1))))x")
                        SliderRow(title: "ROI Padding", value: $roiPadding, range: 0...512, suffix: "px")
                        HStack(spacing: 8) {
                            ForEach([0.0, 128.0, 256.0, 384.0], id: \.self) { padding in
                                Button("\(Int(padding))") {
                                    roiPadding = padding
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        InfoBlock(text: roiHelpText)
                        metricRow("RAFT Iter", "\(cleanupPreset.raftIter)")
                        metricRow(t("Reference Stride", "参考帧间隔"), "\(cleanupPreset.refStride)")
                    }
                    .padding(.vertical, 4)
                }

                GroupBox(t("Output", "输出")) {
                    VStack(spacing: 10) {
                        Toggle(isOn: $autoOutputName) {
                            Label(t("Auto Name", "自动命名"), systemImage: "text.badge.plus")
                        }
                        .toggleStyle(.button)
                        .onChange(of: autoOutputName) { _, enabled in
                            if enabled {
                                outputPath = ""
                            }
                        }
                        if autoOutputName {
                            InfoBlock(text: autoOutputDescription)
                        } else {
                            PathField(title: "Output", text: $outputPath, canChooseDirectory: false, savePanel: true)
                        }
                        Button(action: runCleanup) {
                            Label(t("Run Cleanup", "开始处理"), systemImage: "wand.and.sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.teal)
                        .disabled(videoURL == nil || isRunning)
                        if !completedOutputPath.isEmpty {
                            metricRow(t("Last Output", "上次输出"), URL(fileURLWithPath: completedOutputPath).lastPathComponent)
                            if let completedElapsedSeconds {
                                metricRow(t("Elapsed", "耗时"), "\(completedElapsedSeconds)s")
                            }
                            HStack(spacing: 8) {
                                Button {
                                    openCompletedVideo()
                                } label: {
                                    Label(t("Open Video", "打开视频"), systemImage: "play.rectangle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                Button {
                                    revealCompletedVideo()
                                } label: {
                                    Label(t("Show", "显示"), systemImage: "folder")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox(t("Log", "日志")) {
                    ScrollView {
                        Text(logText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 180)
                }
            }
            .padding(18)
        }
        .frame(width: 360)
    }

    private var rectString: String {
        let rect = pixelRect
        return "\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.width)),\(Int(rect.height))"
    }

    private var pixelRect: CGRect {
        CGRect(
            x: selection.origin.x * videoSize.width,
            y: selection.origin.y * videoSize.height,
            width: selection.width * videoSize.width,
            height: selection.height * videoSize.height
        )
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.callout, design: .monospaced))
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        appLanguage.text(english, chinese)
    }

    private func markModeTitle(_ mode: MarkMode) -> String {
        switch mode {
        case .box: t("Box", "方框")
        case .draw: t("Pen", "钢笔")
        }
    }

    private func presetTitle(_ preset: CleanupPreset) -> String {
        switch preset {
        case .fast: t("Fast", "快速")
        case .balanced: t("Balanced", "平衡")
        case .quality: t("Quality", "质量")
        }
    }

    private func presetDescription(_ preset: CleanupPreset) -> String {
        switch preset {
        case .fast:
            t("Crops to the marked area, half-resolution repair, then composites back.", "只处理标记附近区域，半分辨率修复后贴回原视频。最快。")
        case .balanced:
            t("Recommended: ROI 256, full-resolution repair, balanced speed and quality.", "推荐：ROI 256，原分辨率修复，速度和质量比较平衡。")
        case .quality:
            t("Slower, more conservative temporal repair.", "更慢，更保守，适合质量兜底。")
        }
    }

    private func openVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            setVideoURL(url)
        }
    }

    private func setVideoURL(_ url: URL) {
        let allowedExtensions = ["mp4", "mov", "m4v"]
        guard allowedExtensions.contains(url.pathExtension.lowercased()) else {
            logText = "Unsupported file: \(url.lastPathComponent)\nUse mp4, mov, or m4v."
            return
        }

        videoURL = url
        outputPath = ""
        hasMarked = false
        showMaskPreview = false
        drawnPoints.removeAll()
        isDrawClosed = false
        markMode = .box
        zoomScale = 1.0
        lastExitCode = nil
        completedOutputPath = ""
        completedElapsedSeconds = nil
        loadPreview(from: url)
    }

    private func loadPreview(from url: URL) {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        do {
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            let image = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
            previewImage = image
            videoSize = CGSize(width: cgImage.width, height: cgImage.height)
            logText = "Loaded \(url.lastPathComponent)\nSize \(Int(videoSize.width))x\(Int(videoSize.height))"
        } catch {
            logText = "Could not load preview: \(error.localizedDescription)"
        }
    }

    private func runCleanup() {
        guard let videoURL else { return }
        guard !propainterPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logText = t("Choose your local ProPainter folder before running cleanup.", "开始处理前，请先选择本机 ProPainter 文件夹。")
            return
        }
        guard !pythonPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logText = t("Choose a Python executable before running cleanup.", "开始处理前，请先填写 Python 可执行文件。")
            return
        }
        let requestedOutputURL: URL
        if autoOutputName || outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            requestedOutputURL = defaultOutputURL(for: videoURL)
        } else {
            requestedOutputURL = URL(fileURLWithPath: outputPath)
        }
        let outputURL = protectedOutputURL(requestedOutputURL)
        outputPath = outputURL.path
        guard markMode == .box || (drawnPoints.count >= 3 && isDrawClosed) else {
            logText = "Draw mode needs a closed polygon. Click points around the watermark, then press Close Draw."
            return
        }
        isRunning = true
        cleanupStartedAt = Date()
        elapsedSeconds = 0
        lastExitCode = nil
        completedOutputPath = ""
        completedElapsedSeconds = nil
        logText = "Starting cleanup...\nPreset: \(cleanupPreset.rawValue)\nMask: \(markMode.rawValue)\n"
        let packagePath = pythonPackagePath()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var arguments = [
            pythonPath,
            "-m",
            "watermark_studio.cli",
            "clean",
            videoURL.path,
            outputURL.path,
            "--propainter-dir",
            propainterPath,
            "--python",
            pythonPath,
        ]
        if markMode == .draw {
            arguments += ["--polygon", polygonString]
        } else {
            arguments += ["--rect", rectString]
        }
        arguments += [
            "--expand",
            "\(Int(expandPixels))",
            "--segment-frames",
            "\(cleanupPreset.segmentFrames)",
            "--raft-iter",
            "\(cleanupPreset.raftIter)",
            "--ref-stride",
            "\(cleanupPreset.refStride)",
            "--subvideo-length",
            "\(cleanupPreset.subvideoLength)",
            "--process-scale",
            "\(cleanupPreset.processScale)",
            "--composite-feather",
            "2",
            "--roi-padding",
            "\(Int(roiPadding))",
        ]
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        let existingPythonPath = environment["PYTHONPATH"] ?? ""
        environment["PYTHONPATH"] = [packagePath.path, existingPythonPath].filter { !$0.isEmpty }.joined(separator: ":")
        if environment["PYTORCH_ENABLE_MPS_FALLBACK"] == nil {
            environment["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
        }
        let commonPathPrefixes = ["/opt/homebrew/bin", "/opt/local/bin", "/usr/local/bin"]
        let existingPath = environment["PATH"] ?? ""
        let existingParts = Set(existingPath.split(separator: ":").map(String.init))
        let pathPrefixes = commonPathPrefixes.filter { !existingParts.contains($0) }
        environment["PATH"] = (pathPrefixes + [existingPath]).filter { !$0.isEmpty }.joined(separator: ":")
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                logText += chunk
            }
        }
        process.terminationHandler = { proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                isRunning = false
                let total = cleanupStartedAt.map { max(0, Int(Date().timeIntervalSince($0))) } ?? elapsedSeconds
                elapsedSeconds = total
                completedElapsedSeconds = total
                if proc.terminationStatus == 0 {
                    completedOutputPath = outputURL.path
                }
                lastExitCode = Int(proc.terminationStatus)
                logText += "\nElapsed seconds: \(total)"
                logText += "\nExited with code \(proc.terminationStatus)"
            }
        }

        do {
            try process.run()
        } catch {
            isRunning = false
            cleanupStartedAt = nil
            logText += "\nCould not start process: \(error.localizedDescription)"
        }
    }

    private func pythonPackagePath() -> URL {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("python")
            if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("watermark_studio").path) {
                return bundled
            }
        }

        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src")
    }

    private var polygonString: String {
        drawnPoints
            .map { point in
                let x = min(max(point.x, 0), 1) * videoSize.width
                let y = min(max(point.y, 0), 1) * videoSize.height
                return "\(Int(round(x))),\(Int(round(y)))"
            }
            .joined(separator: ";")
    }

    private var markHelpText: String {
        if markMode == .draw {
            return showMaskPreview ? t("Green is the pen mask. If the edge still leaks, raise Mask Expand by 2-5px.", "绿色区域是钢笔遮罩。边缘还有残留时，把遮罩扩展调到 2-5px。") : t("Click around the watermark edge, then press Close Draw. Pen works better for irregular marks.", "沿水印边缘逐点点击，再点“闭合手绘”。不规则水印用钢笔通常更干净。")
        }
        return showMaskPreview ? t("Green shows the exact cleanup mask, including expand.", "绿色区域是实际处理遮罩，包含扩展范围。") : t("Box works for regular watermarks. For small or irregular marks, switch to Pen.", "方框适合规则水印；很小或不规则的水印，建议切到钢笔。")
    }

    private var drawStatus: String {
        let suffix = isDrawClosed ? "closed" : "open"
        return "\(drawnPoints.count) points · \(suffix)"
    }

    private var roiHelpText: String {
        t("Recommended: Fast 128, Balanced 256, Quality 0. 0 processes the full frame; higher values keep more background around the mask but run slower.", "推荐：快速 128，平衡 256，质量 0。0 表示整帧处理；数值越大，保留的背景参考越多，但越慢。")
    }

    private var autoOutputDescription: String {
        guard let videoURL else {
            return t("Output filename will be generated when cleanup starts.", "开始处理时会自动生成输出文件名。")
        }
        let basename = videoURL.deletingPathExtension().lastPathComponent
        return "\(basename)_cleaned_\(cleanupPreset.rawValue.lowercased())_roi\(Int(roiPadding))_[timestamp].mp4"
    }

    private func openCompletedVideo() {
        guard !completedOutputPath.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: completedOutputPath))
    }

    private func revealCompletedVideo() {
        guard !completedOutputPath.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: completedOutputPath)])
    }

    private func defaultOutputURL(for inputURL: URL) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        let timestamp = formatter.string(from: Date())
        let preset = cleanupPreset.rawValue.lowercased()
        let roi = Int(roiPadding)
        let basename = inputURL.deletingPathExtension().lastPathComponent
        let filename = "\(basename)_cleaned_\(preset)_roi\(roi)_\(timestamp).mp4"
        return uniqueURL(inputURL.deletingLastPathComponent().appendingPathComponent(filename))
    }

    private func protectedOutputURL(_ url: URL) -> URL {
        uniqueURL(url)
    }

    private func uniqueURL(_ url: URL) -> URL {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return url }

        let directory = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        for index in 2..<1000 {
            let candidate = directory.appendingPathComponent("\(stem)_\(String(format: "%02d", index)).\(ext)")
            if !manager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return directory.appendingPathComponent("\(stem)_\(UUID().uuidString).\(ext)")
    }
}

struct Sidebar: View {
    let language: AppLanguage
    let videoURL: URL?
    let hasMarked: Bool
    let showMaskPreview: Bool
    let isRunning: Bool
    let lastExitCode: Int?

    var body: some View {
        List {
            Section(t("Workflow", "流程")) {
                WorkflowRow(title: t("Open Video", "打开视频"), subtitle: videoURL?.lastPathComponent ?? t("Drop or choose a file", "拖入或选择文件"), systemImage: videoURL == nil ? "1.circle" : "checkmark.circle.fill", isActive: videoURL == nil, isDone: videoURL != nil)
                WorkflowRow(title: t("Mark", "标记"), subtitle: hasMarked ? t("Selection updated", "已更新标记") : t("Drag the box", "拖动标记框"), systemImage: hasMarked ? "checkmark.circle.fill" : "selection.pin.in.out", isActive: videoURL != nil && !hasMarked, isDone: hasMarked)
                WorkflowRow(title: t("Preview Mask", "预览遮罩"), subtitle: showMaskPreview ? t("Mask visible", "遮罩可见") : t("Toggle in Mark panel", "在标记面板开启"), systemImage: showMaskPreview ? "eye.fill" : "eye", isActive: videoURL != nil && hasMarked && !showMaskPreview, isDone: showMaskPreview)
                WorkflowRow(title: t("Run Cleanup", "开始处理"), subtitle: cleanupSubtitle, systemImage: cleanupIcon, isActive: isRunning, isDone: lastExitCode == 0)
            }
            Section(t("Tips", "提示")) {
                InfoBlock(text: t("Pen masks are usually cleaner for irregular watermarks. Use Mask Expand 2-5px only when the edge still leaks.", "不规则水印通常用钢笔更干净。边缘还有残留时，再把遮罩扩展调到 2-5px。"), accent: .teal)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }
        }
        .navigationTitle("Watermark Studio")
        .frame(minWidth: 280)
    }

    private var cleanupIcon: String {
        if isRunning { return "progress.indicator" }
        if lastExitCode == 0 { return "checkmark.circle.fill" }
        if lastExitCode != nil { return "exclamationmark.triangle.fill" }
        return "play.circle"
    }

    private var cleanupSubtitle: String {
        if isRunning { return t("Processing", "处理中") }
        if lastExitCode == 0 { return t("Done", "完成") }
        if let lastExitCode { return t("Exited \(lastExitCode)", "退出码 \(lastExitCode)") }
        return t("Ready when marked", "标记后可处理")
    }

    private func t(_ english: String, _ chinese: String) -> String {
        language.text(english, chinese)
    }
}

struct MarkableVideoView: View {
    let image: NSImage
    @Binding var selection: CGRect
    let markMode: MarkMode
    @Binding var drawnPoints: [CGPoint]
    @Binding var isDrawClosed: Bool
    let showMaskPreview: Bool
    let expandPixels: Double
    let videoSize: CGSize
    let onEdited: () -> Void

    var body: some View {
        MarkingCanvasView(
            image: image,
            selection: $selection,
            markMode: markMode,
            drawnPoints: $drawnPoints,
            isDrawClosed: $isDrawClosed,
            showMaskPreview: showMaskPreview,
            expandPixels: expandPixels,
            videoSize: videoSize,
            onEdited: onEdited
        )
    }
}

private struct MarkingCanvasView: NSViewRepresentable {
    let image: NSImage
    @Binding var selection: CGRect
    let markMode: MarkMode
    @Binding var drawnPoints: [CGPoint]
    @Binding var isDrawClosed: Bool
    let showMaskPreview: Bool
    let expandPixels: Double
    let videoSize: CGSize
    let onEdited: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> MarkingCanvasNSView {
        let view = MarkingCanvasNSView()
        view.onSelectionChanged = { rect in
            selection = rect
            onEdited()
        }
        view.onPointAdded = { point in
            drawnPoints.append(point)
            onEdited()
        }
        return view
    }

    func updateNSView(_ view: MarkingCanvasNSView, context: Context) {
        view.image = image
        view.selection = selection
        view.markMode = markMode
        view.drawnPoints = drawnPoints
        view.isDrawClosed = isDrawClosed
        view.showMaskPreview = showMaskPreview
        view.expandPixels = expandPixels
        view.videoSize = videoSize
        view.needsDisplay = true
    }

    final class Coordinator {
        var parent: MarkingCanvasView

        init(_ parent: MarkingCanvasView) {
            self.parent = parent
        }
    }
}

private final class MarkingCanvasNSView: NSView {
    enum DragMode {
        case none
        case move
        case resize(left: Bool, right: Bool, top: Bool, bottom: Bool)
    }

    var image: NSImage?
    var selection = CGRect.zero
    var markMode: MarkMode = .box
    var drawnPoints: [CGPoint] = []
    var isDrawClosed = false
    var showMaskPreview = false
    var expandPixels = 0.0
    var videoSize = CGSize(width: 720, height: 1280)
    var onSelectionChanged: ((CGRect) -> Void)?
    var onPointAdded: ((CGPoint) -> Void)?

    private var dragMode = DragMode.none
    private var dragStartSelection = CGRect.zero
    private var dragStartPoint = CGPoint.zero

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image else { return }
        let fitted = fittedRect(imageSize: image.size, container: bounds.size)
        image.draw(in: fitted, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

        if showMaskPreview {
            NSColor.systemGreen.withAlphaComponent(0.30).setFill()
            if markMode == .box {
                normalizedRectToView(expandedSelection, fitted: fitted).fill()
            } else if isDrawClosed {
                polygonPath(fitted: fitted, close: true).fill()
            }
        }

        NSColor.coralNS.withAlphaComponent(0.18).setFill()
        NSColor.coralNS.setStroke()
        if markMode == .box {
            let rect = normalizedRectToView(selection, fitted: fitted)
            rect.fill()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2
            path.stroke()
            NSColor.coralNS.setFill()
            for handle in handleRects(selectionRect: rect) {
                NSBezierPath(ovalIn: handle).fill()
            }
        } else {
            let path = polygonPath(fitted: fitted, close: isDrawClosed)
            path.lineWidth = 3
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()
            for (index, point) in drawnPoints.enumerated() {
                drawPoint(index: index, at: viewPoint(point, fitted: fitted))
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let fitted = fittedRectForCurrentImage()
        guard fitted.contains(point) else {
            dragMode = .none
            return
        }

        if markMode == .draw {
            guard !isDrawClosed else { return }
            onPointAdded?(normalizedPoint(point, fitted: fitted))
            return
        }

        let selectionRect = normalizedRectToView(selection, fitted: fitted)
        if let resizeMode = resizeMode(at: point, selectionRect: selectionRect) {
            dragMode = resizeMode
        } else if selectionRect.contains(point) {
            dragMode = .move
        } else {
            dragMode = .none
        }
        dragStartPoint = point
        dragStartSelection = selection
    }

    override func mouseDragged(with event: NSEvent) {
        guard markMode == .box else { return }
        if case .none = dragMode { return }
        let point = convert(event.locationInWindow, from: nil)
        let fitted = fittedRectForCurrentImage()
        let dx = (point.x - dragStartPoint.x) / max(fitted.width, 1)
        let dy = (point.y - dragStartPoint.y) / max(fitted.height, 1)
        var next = dragStartSelection

        switch dragMode {
        case .move:
            next.origin.x = min(max(dragStartSelection.origin.x + dx, 0), 1 - dragStartSelection.width)
            next.origin.y = min(max(dragStartSelection.origin.y + dy, 0), 1 - dragStartSelection.height)
        case let .resize(left, right, top, bottom):
            next = resizedSelection(from: dragStartSelection, dx: dx, dy: dy, left: left, right: right, top: top, bottom: bottom)
        case .none:
            break
        }

        selection = next
        onSelectionChanged?(next)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = .none
    }

    private func fittedRectForCurrentImage() -> CGRect {
        fittedRect(imageSize: image?.size ?? CGSize(width: 720, height: 1280), container: bounds.size)
    }

    private func normalizedPoint(_ point: CGPoint, fitted: CGRect) -> CGPoint {
        CGPoint(
            x: min(max((point.x - fitted.minX) / max(fitted.width, 1), 0), 1),
            y: min(max((point.y - fitted.minY) / max(fitted.height, 1), 0), 1)
        )
    }

    private func viewPoint(_ point: CGPoint, fitted: CGRect) -> CGPoint {
        CGPoint(x: fitted.minX + point.x * fitted.width, y: fitted.minY + point.y * fitted.height)
    }

    private func normalizedRectToView(_ rect: CGRect, fitted: CGRect) -> CGRect {
        CGRect(
            x: fitted.minX + rect.minX * fitted.width,
            y: fitted.minY + rect.minY * fitted.height,
            width: rect.width * fitted.width,
            height: rect.height * fitted.height
        )
    }

    private func handleRects(selectionRect: CGRect) -> [CGRect] {
        let points = [
            CGPoint(x: selectionRect.minX, y: selectionRect.minY),
            CGPoint(x: selectionRect.midX, y: selectionRect.minY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.minY),
            CGPoint(x: selectionRect.minX, y: selectionRect.midY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.midY),
            CGPoint(x: selectionRect.minX, y: selectionRect.maxY),
            CGPoint(x: selectionRect.midX, y: selectionRect.maxY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.maxY),
        ]
        return points.map { CGPoint in
            CGRect(x: CGPoint.x - 5, y: CGPoint.y - 5, width: 10, height: 10)
        }
    }

    private func resizeMode(at point: CGPoint, selectionRect: CGRect) -> DragMode? {
        let hit = max(18.0, min(selectionRect.width, selectionRect.height) * 0.20)
        let nearLeft = abs(point.x - selectionRect.minX) <= hit
        let nearRight = abs(point.x - selectionRect.maxX) <= hit
        let nearTop = abs(point.y - selectionRect.minY) <= hit
        let nearBottom = abs(point.y - selectionRect.maxY) <= hit
        let expanded = selectionRect.insetBy(dx: -hit, dy: -hit)
        guard expanded.contains(point) else { return nil }
        guard nearLeft || nearRight || nearTop || nearBottom else { return nil }
        return .resize(left: nearLeft && !nearRight, right: nearRight, top: nearTop && !nearBottom, bottom: nearBottom)
    }

    private func resizedSelection(
        from start: CGRect,
        dx: CGFloat,
        dy: CGFloat,
        left: Bool,
        right: Bool,
        top: Bool,
        bottom: Bool
    ) -> CGRect {
        let minSize = 0.02
        var minX = start.minX
        var maxX = start.maxX
        var minY = start.minY
        var maxY = start.maxY

        if left {
            minX = min(max(start.minX + dx, 0), maxX - minSize)
        }
        if right {
            maxX = max(min(start.maxX + dx, 1), minX + minSize)
        }
        if top {
            minY = min(max(start.minY + dy, 0), maxY - minSize)
        }
        if bottom {
            maxY = max(min(start.maxY + dy, 1), minY + minSize)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func polygonPath(fitted: CGRect, close: Bool) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = drawnPoints.first else { return path }
        path.move(to: viewPoint(first, fitted: fitted))
        for point in drawnPoints.dropFirst() {
            path.line(to: viewPoint(point, fitted: fitted))
        }
        if close {
            path.close()
        }
        return path
    }

    private func drawPoint(index: Int, at point: CGPoint) {
        let rect = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
        NSColor.coralNS.setFill()
        NSBezierPath(ovalIn: rect).fill()
        let text = "\(index + 1)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 8),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), withAttributes: attrs)
    }

    private var expandedSelection: CGRect {
        let dx = expandPixels / max(videoSize.width, 1)
        let dy = expandPixels / max(videoSize.height, 1)
        let minX = max(0, selection.minX - dx)
        let minY = max(0, selection.minY - dy)
        let maxX = min(1, selection.maxX + dx)
        let maxY = min(1, selection.maxY + dy)
        return CGRect(x: minX, y: minY, width: max(0.001, maxX - minX), height: max(0.001, maxY - minY))
    }

    private func fittedRect(imageSize: CGSize, container: CGSize) -> CGRect {
        let imageRatio = imageSize.width / max(imageSize.height, 1)
        let containerRatio = container.width / max(container.height, 1)
        if imageRatio > containerRatio {
            let h = container.width / imageRatio
            return CGRect(x: 0, y: (container.height - h) / 2, width: container.width, height: h)
        } else {
            let w = container.height * imageRatio
            return CGRect(x: (container.width - w) / 2, y: 0, width: w, height: container.height)
        }
    }
}

struct ResizeHandle: View {
    @Binding var selection: CGRect
    let fitted: CGRect
    let onEdited: () -> Void
    @State private var start: CGRect?

    var body: some View {
        Circle()
            .fill(Color.coral)
            .frame(width: 12, height: 12)
            .position(
                x: fitted.minX + selection.maxX * fitted.width,
                y: fitted.minY + selection.maxY * fitted.height
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if start == nil { start = selection }
                        guard let start else { return }
                        let dw = value.translation.width / max(fitted.width, 1)
                        let dh = value.translation.height / max(fitted.height, 1)
                        selection.size.width = min(max(start.width + dw, 0.02), 1 - selection.origin.x)
                        selection.size.height = min(max(start.height + dh, 0.02), 1 - selection.origin.y)
                        onEdited()
                    }
                    .onEnded { _ in start = nil }
            )
    }
}

final class CursorZoomNSScrollView: NSScrollView {
    var onZoomChanged: ((CGFloat) -> Void)?
    var currentZoomScale: CGFloat = 1
    var minZoomScale: CGFloat = 1
    var maxZoomScale: CGFloat = 4
    private var pendingAnchor: (unit: CGPoint, viewport: CGPoint)?

    override func magnify(with event: NSEvent) {
        let factor = 1 + event.magnification
        zoom(to: currentZoomScale * factor, event: event)
    }

    override func smartMagnify(with event: NSEvent) {
        let target: CGFloat = currentZoomScale < 1.5 ? 2.0 : 1.0
        zoom(to: target, event: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY == 0 ? -event.scrollingDeltaX : event.scrollingDeltaY
        let factor = exp(delta * 0.0045)
        zoom(to: currentZoomScale * factor, event: event)
    }

    private func zoom(to rawScale: CGFloat, event: NSEvent) {
        guard let documentView else { return }
        let target = min(max(rawScale, minZoomScale), maxZoomScale)
        let documentSize = documentView.frame.size
        guard documentSize.width > 0, documentSize.height > 0 else { return }
        let windowPoint = event.locationInWindow
        let documentPoint = documentView.convert(windowPoint, from: nil)
        let clipPoint = contentView.convert(windowPoint, from: nil)
        let viewportPoint = CGPoint(
            x: clipPoint.x - contentView.bounds.origin.x,
            y: clipPoint.y - contentView.bounds.origin.y
        )
        pendingAnchor = (
            unit: CGPoint(x: documentPoint.x / documentSize.width, y: documentPoint.y / documentSize.height),
            viewport: viewportPoint
        )
        onZoomChanged?(target)
    }

    func applyPendingAnchor() {
        guard let pendingAnchor, let documentView else { return }
        let documentSize = documentView.frame.size
        let targetPoint = CGPoint(
            x: pendingAnchor.unit.x * documentSize.width,
            y: pendingAnchor.unit.y * documentSize.height
        )
        let maxX = max(0, documentSize.width - contentView.bounds.width)
        let maxY = max(0, documentSize.height - contentView.bounds.height)
        let origin = CGPoint(
            x: min(max(targetPoint.x - pendingAnchor.viewport.x, 0), maxX),
            y: min(max(targetPoint.y - pendingAnchor.viewport.y, 0), maxY)
        )
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
        self.pendingAnchor = nil
    }
}

struct CursorZoomScrollView<Content: View>: NSViewRepresentable {
    @Binding var zoomScale: Double
    let baseSize: CGSize
    let minZoom: Double
    let maxZoom: Double
    let content: Content

    init(
        zoomScale: Binding<Double>,
        baseSize: CGSize,
        minZoom: Double,
        maxZoom: Double,
        @ViewBuilder content: () -> Content
    ) {
        _zoomScale = zoomScale
        self.baseSize = baseSize
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> CursorZoomNSScrollView {
        let scrollView = CursorZoomNSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = false
        scrollView.minZoomScale = CGFloat(minZoom)
        scrollView.maxZoomScale = CGFloat(maxZoom)
        scrollView.currentZoomScale = CGFloat(zoomScale)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let scaledSize = CGSize(width: baseSize.width * zoomScale, height: baseSize.height * zoomScale)
        let hostingView = NSHostingView(rootView: AnyView(content.frame(width: scaledSize.width, height: scaledSize.height)))
        hostingView.frame = NSRect(origin: .zero, size: scaledSize)
        scrollView.documentView = hostingView
        context.coordinator.hostingView = hostingView
        scrollView.onZoomChanged = { scale in
            DispatchQueue.main.async {
                if abs(zoomScale - Double(scale)) > 0.01 {
                    zoomScale = Double(scale)
                }
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: CursorZoomNSScrollView, context: Context) {
        let zoom = min(max(zoomScale, minZoom), maxZoom)
        let size = CGSize(width: max(baseSize.width * zoom, 1), height: max(baseSize.height * zoom, 1))
        let hostingView = context.coordinator.hostingView ?? NSHostingView(rootView: AnyView(content.frame(width: size.width, height: size.height)))
        if hostingView.superview == nil {
            scrollView.documentView = hostingView
            context.coordinator.hostingView = hostingView
        }
        hostingView.rootView = AnyView(content.frame(width: size.width, height: size.height))
        hostingView.frame = NSRect(origin: .zero, size: size)
        scrollView.minZoomScale = CGFloat(minZoom)
        scrollView.maxZoomScale = CGFloat(maxZoom)
        scrollView.currentZoomScale = CGFloat(zoom)
        scrollView.applyPendingAnchor()
    }

    final class Coordinator {
        var parent: CursorZoomScrollView
        var hostingView: NSHostingView<AnyView>?

        init(_ parent: CursorZoomScrollView) {
            self.parent = parent
        }
    }
}

struct InfoBlock: View {
    let text: String
    var accent: Color = .teal

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 3)
                .padding(.vertical, 2)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct WorkflowRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isActive: Bool
    let isDone: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(isDone ? Color.teal : isActive ? Color.accentColor : Color.secondary)
                .font(.callout)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(isActive ? .semibold : .regular))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value)) \(suffix)")
                    .foregroundStyle(.secondary)
                    .font(.system(.callout, design: .monospaced))
            }
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let progress = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
                let knobSize: CGFloat = 18
                let knobX = min(max(width * progress, knobSize / 2), width - knobSize / 2)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 6)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: knobX, height: 6)
                    Circle()
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .frame(width: knobSize, height: knobSize)
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                        .overlay(Circle().stroke(Color.secondary.opacity(0.16), lineWidth: 1))
                        .offset(x: knobX - knobSize / 2)
                }
                .frame(height: 22)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            setValue(from: drag.location.x, width: width)
                        }
                )
            }
            .frame(height: 22)
        }
    }

    private func setValue(from x: CGFloat, width: CGFloat) {
        let clamped = min(max(Double(x / max(width, 1)), 0), 1)
        let rawValue = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
        value = min(max(rawValue.rounded(), range.lowerBound), range.upperBound)
    }
}

struct PathField: View {
    let title: String
    @Binding var text: String
    var canChooseDirectory = false
    var savePanel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.callout.weight(.medium))
            HStack {
                TextField(title, text: $text)
                    .textFieldStyle(.roundedBorder)
                Button {
                    choose()
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
    }

    private func choose() {
        if savePanel {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.mpeg4Movie]
            if panel.runModal() == .OK, let url = panel.url {
                text = url.path
            }
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = !canChooseDirectory
        panel.canChooseDirectories = canChooseDirectory
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            text = url.path
        }
    }
}

struct ProgressTimeline: View {
    let language: AppLanguage
    let segmentFrames: Int
    let isRunning: Bool
    let elapsedSeconds: Int
    let lastExitCode: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(progressTitle)
                    .font(.callout.weight(.medium))
                Spacer()
                Text(progressDetail)
                    .foregroundStyle(.secondary)
            }
            if isRunning {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.orange)
                Text(t("Live output is in the log panel. ProPainter does not report exact total percentage yet.", "实时输出在日志里。ProPainter 目前不会报告精确总进度百分比。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(lastExitCode == 0 ? Color.teal : Color.secondary.opacity(0.22))
                    .frame(height: 8)
            }
        }
    }

    private var progressTitle: String {
        if isRunning { return t("Processing Video", "正在处理视频") }
        if lastExitCode == 0 { return t("Cleanup Complete", "处理完成") }
        if lastExitCode != nil { return t("Cleanup Failed", "处理失败") }
        return t("Cleanup Status", "处理状态")
    }

    private var progressDetail: String {
        if isRunning { return "\(elapsedSeconds)s \(t("elapsed", "已用")) · \(segmentFrames) \(t("frames/chunk", "帧/段"))" }
        if let lastExitCode { return t("exit \(lastExitCode)", "退出码 \(lastExitCode)") }
        return "\(segmentFrames) \(t("frames/chunk", "帧/段"))"
    }

    private func t(_ english: String, _ chinese: String) -> String {
        language.text(english, chinese)
    }
}

extension Color {
    static let coral = Color(red: 0.94, green: 0.34, blue: 0.27)
}

extension NSColor {
    static let coralNS = NSColor(red: 0.94, green: 0.34, blue: 0.27, alpha: 1.0)
}
