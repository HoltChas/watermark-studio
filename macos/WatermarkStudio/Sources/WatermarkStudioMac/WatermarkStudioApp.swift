import AVFoundation
import SwiftUI

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
        window.contentView = NSHostingView(rootView: content)
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

    var description: String {
        switch self {
        case .fast:
            "Faster first pass, slightly softer motion detail."
        case .balanced:
            "The tested Axolotl production setting."
        case .quality:
            "Slower, more conservative temporal repair."
        }
    }
}

struct ContentView: View {
    @State private var videoURL: URL?
    @State private var previewImage: NSImage?
    @State private var videoSize: CGSize = CGSize(width: 720, height: 1280)
    @State private var selection = CGRect(x: 0.78, y: 0.88, width: 0.12, height: 0.07)
    @State private var pythonPath = "/opt/homebrew/anaconda3/bin/python3"
    @State private var propainterPath = "/Users/haocongxing/Documents/kiddo enlish/tools/ProPainter"
    @State private var outputPath = ""
    @State private var expandPixels = 3.0
    @State private var cleanupPreset: CleanupPreset = .balanced
    @State private var logText = "Ready"
    @State private var isRunning = false

    var body: some View {
        NavigationSplitView {
            Sidebar(videoURL: videoURL, isRunning: isRunning)
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
                    Label("Open Video", systemImage: "folder")
                }
                Button(action: runCleanup) {
                    Label(isRunning ? "Running" : "Run Cleanup", systemImage: "play.circle.fill")
                }
                .disabled(videoURL == nil || isRunning)
            }
        }
    }

    private var previewPane: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Watermark Studio")
                        .font(.system(size: 28, weight: .semibold))
                    Text(videoURL?.lastPathComponent ?? "Open a video and drag the box over the watermark.")
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
                    MarkableVideoView(image: previewImage, selection: $selection)
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
                            Text("The first frame appears here. Drag the selection box to cover the watermark.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)

            ProgressTimeline(segmentFrames: cleanupPreset.segmentFrames, isRunning: isRunning)
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isRunning ? Color.orange : Color.teal)
                .frame(width: 8, height: 8)
            Text(isRunning ? "Running" : "Ready")
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Mark") {
                    VStack(alignment: .leading, spacing: 10) {
                        metricRow("Video", "\(Int(videoSize.width)) x \(Int(videoSize.height))")
                        metricRow("Rect", rectString)
                        SliderRow(title: "Mask Expand", value: $expandPixels, range: 0...24, suffix: "px")
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Backend") {
                    VStack(spacing: 10) {
                        Picker("Speed", selection: $cleanupPreset) {
                            ForEach(CleanupPreset.allCases) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(cleanupPreset.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        PathField(title: "Python", text: $pythonPath, canChooseDirectory: false)
                        PathField(title: "ProPainter", text: $propainterPath, canChooseDirectory: true)
                        metricRow("Segment Length", "\(cleanupPreset.segmentFrames) frames")
                        metricRow("RAFT Iter", "\(cleanupPreset.raftIter)")
                        metricRow("Reference Stride", "\(cleanupPreset.refStride)")
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Output") {
                    VStack(spacing: 10) {
                        PathField(title: "Output", text: $outputPath, canChooseDirectory: false, savePanel: true)
                        Button(action: runCleanup) {
                            Label("Run Cleanup", systemImage: "wand.and.sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.teal)
                        .disabled(videoURL == nil || isRunning)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Log") {
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

    private func openVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            videoURL = url
            outputPath = url.deletingPathExtension().appendingPathExtension("cleaned.mp4").path
            loadPreview(from: url)
        }
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
        if outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            outputPath = videoURL.deletingPathExtension().appendingPathExtension("cleaned.mp4").path
        }
        isRunning = true
        logText = "Starting cleanup...\nPreset: \(cleanupPreset.rawValue)\n"
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            pythonPath,
            "-m",
            "watermark_studio.cli",
            "clean",
            videoURL.path,
            outputPath,
            "--propainter-dir",
            propainterPath,
            "--python",
            pythonPath,
            "--rect",
            rectString,
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
        ]
        process.environment = [
            "PYTHONPATH": repoRoot.appendingPathComponent("src").path,
            "PYTORCH_ENABLE_MPS_FALLBACK": "1",
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        ]

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
            DispatchQueue.main.async {
                isRunning = false
                logText += "\nExited with code \(proc.terminationStatus)"
            }
        }

        do {
            try process.run()
        } catch {
            isRunning = false
            logText += "\nCould not start process: \(error.localizedDescription)"
        }
    }
}

struct Sidebar: View {
    let videoURL: URL?
    let isRunning: Bool

    var body: some View {
        List {
            Section("Workflow") {
                Label("Open Video", systemImage: videoURL == nil ? "1.circle" : "checkmark.circle.fill")
                Label("Mark", systemImage: videoURL == nil ? "2.circle" : "selection.pin.in.out")
                Label("Preview Mask", systemImage: "eye")
                Label("Run Cleanup", systemImage: isRunning ? "progress.indicator" : "play.circle")
            }
            Section("Tips") {
                Text("Keep the box tight. Use Expand for soft edges.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Watermark Studio")
        .frame(minWidth: 210)
    }
}

struct MarkableVideoView: View {
    let image: NSImage
    @Binding var selection: CGRect
    @State private var dragStart: CGRect?

    var body: some View {
        GeometryReader { proxy in
            let fitted = fittedRect(imageSize: image.size, container: proxy.size)
            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)

                Rectangle()
                    .strokeBorder(Color.coral, lineWidth: 2)
                    .background(Color.coral.opacity(0.18))
                    .frame(width: selection.width * fitted.width, height: selection.height * fitted.height)
                    .position(
                        x: fitted.minX + selection.midX * fitted.width,
                        y: fitted.minY + selection.midY * fitted.height
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if dragStart == nil { dragStart = selection }
                                guard let start = dragStart else { return }
                                let dx = value.translation.width / max(fitted.width, 1)
                                let dy = value.translation.height / max(fitted.height, 1)
                                selection.origin.x = min(max(start.origin.x + dx, 0), 1 - selection.width)
                                selection.origin.y = min(max(start.origin.y + dy, 0), 1 - selection.height)
                            }
                            .onEnded { _ in dragStart = nil }
                    )

                ResizeHandle(selection: $selection, fitted: fitted)
            }
        }
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
                    }
                    .onEnded { _ in start = nil }
            )
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value)) \(suffix)")
                    .foregroundStyle(.secondary)
                    .font(.system(.callout, design: .monospaced))
            }
            Slider(value: $value, in: range, step: 1)
        }
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
    let segmentFrames: Int
    let isRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Segment Progress")
                    .font(.callout.weight(.medium))
                Spacer()
                Text("\(segmentFrames) frames per chunk")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isRunning && index == 0 ? Color.orange : Color.teal.opacity(0.28))
                        .frame(height: 8)
                }
            }
        }
    }
}

extension Color {
    static let coral = Color(red: 0.94, green: 0.34, blue: 0.27)
}
