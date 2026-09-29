import SwiftUI
import ScreenCaptureKit
import CoreImage
import CoreMedia

struct PreviewPaused: LocalizedError {
    var errorDescription: String? { "源窗口暂不可见" }
}

// Keep at most one frame waiting for the UI; stream callbacks never queue a backlog.
private final class PreviewStreamSink: NSObject, SCStreamOutput, SCStreamDelegate {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private var delivering = false
    let onFrame: (CGImage, PreviewStreamSink) -> Void
    let onError: (Error) -> Void

    init(onFrame: @escaping (CGImage, PreviewStreamSink) -> Void, onError: @escaping (Error) -> Void) {
        self.onFrame = onFrame; self.onError = onError
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        guard !delivering else { lock.unlock(); return }
        delivering = true; lock.unlock()
        let image = CIImage(cvPixelBuffer: buffer)
        guard let frame = context.createCGImage(image, from: image.extent) else { finished(); return }
        onFrame(frame, self)
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { onError(error) }
    func finished() { lock.lock(); delivering = false; lock.unlock() }
}

// A single in-flight capture and a single displayed image: no frame backlog or recordings.
final class FloatingPreview: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var image: CGImage?
    @Published private(set) var status = "尚未开始预览"
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var frameRate = 5
    @Published private(set) var actualFPS = 0
    private(set) var panel: NSPanel?
    private var captureTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    private var stream: SCStream?
    private var streamSink: PreviewStreamSink?
    private var generation = UUID()
    private var frameCount = 0
    private var frameCountStarted = ContinuousClock.now
    static let frameRates = [1, 2, 5, 30, 60]

    func setFrameRate(_ value: Int) {
        guard Self.frameRates.contains(value) else { return }
        frameRate = value
    }

    static func frameInterval(for value: Int) -> Duration { .nanoseconds(1_000_000_000 / max(1, value)) }

    static func pixelSize(for size: CGSize) -> CGSize {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return CGSize(width: 640, height: 400) }
        let scale = min(2, 1600 / max(size.width, size.height))
        return CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
    }

    @available(macOS 14.0, *)
    static func streamConfiguration(size: CGSize, frameRate: Int) -> SCStreamConfiguration {
        let pixels = pixelSize(for: size)
        let config = SCStreamConfiguration()
        config.width = Int(pixels.width); config.height = Int(pixels.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.queueDepth = 3
        config.showsCursor = false; config.capturesAudio = false
        config.scalesToFit = true; config.preservesAspectRatio = true
        config.ignoreShadowsSingleWindow = true
        return config
    }

    func begin(title: String, showPanel: Bool = true, capture: @escaping () async throws -> CGImage) {
        let token = openPanel(title: title, showPanel: showPanel)
        // ponytail: low-rate screenshots avoid a stream; high rates use SCStream below.
        captureTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    let started = ContinuousClock.now
                    let frame = try await capture()
                    guard !Task.isCancelled, let self, self.generation == token else { return }
                    self.image = frame; self.isPaused = false
                    self.status = "只读预览 · 拖动边框调整大小"
                    try await Task.sleep(until: started.advanced(by: Self.frameInterval(for: self.frameRate)), clock: .continuous)
                } catch {
                    guard !Task.isCancelled, let self, self.generation == token else { return }
                    if error is PreviewPaused {
                        if !self.isPaused {
                            self.isPaused = true
                            self.status = "预览已暂停：源窗口暂不可见，恢复后自动继续"
                        }
                        // ponytail: while paused, query window visibility ~once/second, never request a screenshot.
                        do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                        continue
                    }
                    self.image = nil; self.isPaused = false; self.isRunning = false
                    self.status = "预览已停止：\(error.localizedDescription)"
                    self.captureTask = nil
                    return
                }
            }
        }
    }

    @available(macOS 14.0, *)
    func beginStream(title: String, window: SCWindow, showPanel: Bool = true,
                     visible: @escaping () async throws -> Bool) {
        let token = openPanel(title: title, showPanel: showPanel)
        let config = Self.streamConfiguration(size: window.frame.size, frameRate: frameRate)
        let sink = PreviewStreamSink(onFrame: { [weak self] frame, sink in
            Task { @MainActor [weak self] in
                defer { sink.finished() }
                guard let self, self.generation == token, self.isRunning, !self.isPaused else { return }
                let firstFrame = self.image == nil
                self.image = frame
                if firstFrame { self.status = "只读预览 · 上限 \(self.frameRate) FPS" }
                self.frameCount += 1
                let now = ContinuousClock.now
                let elapsed = self.frameCountStarted.duration(to: now)
                if elapsed >= .seconds(1) {
                    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                    self.actualFPS = Int((Double(self.frameCount) / seconds).rounded())
                    self.frameCount = 0; self.frameCountStarted = now
                    self.status = "只读预览 · 实际 \(self.actualFPS) FPS（上限 \(self.frameRate)）"
                }
            }
        }, onError: { [weak self] error in
            Task { @MainActor [weak self] in self?.streamFailed(error, token: token) }
        })
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: sink)
        self.stream = stream; streamSink = sink
        streamTask = Task { @MainActor [weak self] in
            var capturing = false
            defer { if capturing { Task { try? await stream.stopCapture() } } }
            do {
                try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: DispatchQueue(label: "mactools.preview.frames"))
                try await stream.startCapture()
                capturing = true
                while !Task.isCancelled {
                    guard let self, self.generation == token else { return }
                    let onScreen = try await visible()
                    guard !Task.isCancelled, self.generation == token else { return }
                    let wasPaused = self.isPaused
                    self.isPaused = !onScreen
                    if !onScreen {
                        self.status = "预览已暂停：源窗口暂不可见，恢复后自动继续"
                        self.actualFPS = 0; self.frameCount = 0; self.frameCountStarted = .now
                        if capturing { try await stream.stopCapture(); capturing = false }
                    } else if !capturing {
                        self.status = "源窗口已恢复 · 等待新画面"
                        self.frameCount = 0; self.frameCountStarted = .now
                        try await stream.startCapture(); capturing = true
                    } else if wasPaused {
                        self.status = "源窗口已恢复 · 等待新画面"
                    }
                    try await Task.sleep(for: .seconds(1))
                }
            } catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.streamFailed(error, token: token)
            }
        }
    }

    private func openPanel(title: String, showPanel: Bool) -> UUID {
        stop()
        let token = generation
        status = "等待画面…"; isRunning = true; isPaused = false
        actualFPS = 0; frameCount = 0; frameCountStarted = .now
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
                            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "悬浮预览 · \(title)"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentMinSize = NSSize(width: 240, height: 160)
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: FloatingPreviewView(preview: self))
        panel.center()
        self.panel = panel
        if showPanel { panel.orderFrontRegardless() }
        return token
    }

    private func streamFailed(_ error: Error, token: UUID) {
        guard generation == token, isRunning else { return }
        streamTask?.cancel(); streamTask = nil
        stream = nil; streamSink = nil
        image = nil; isPaused = false; isRunning = false
        actualFPS = 0
        status = "预览已停止：\(error.localizedDescription)"
    }

    func stop() {
        generation = UUID()
        captureTask?.cancel(); captureTask = nil
        streamTask?.cancel(); streamTask = nil
        stream = nil; streamSink = nil
        image = nil; isRunning = false; isPaused = false; actualFPS = 0; status = "尚未开始预览"
        panel?.delegate = nil
        panel?.contentView = nil
        panel?.close(); panel = nil
    }
    func windowWillClose(_ notification: Notification) { stop() }
    deinit { captureTask?.cancel(); streamTask?.cancel() }
}

private struct FloatingPreviewView: View {
    @ObservedObject var preview: FloatingPreview
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                if let image = preview.image {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                        .opacity(preview.isPaused ? 0.55 : 1)
                        .accessibilityLabel(preview.isPaused ? "已暂停的上一帧画面" : "所选窗口的只读画面")
                }
                if preview.isPaused {
                    Label("已暂停 · 恢复源窗口后自动继续", systemImage: "pause.circle.fill")
                        .font(.callout.weight(.medium)).padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Text(preview.status).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Text(preview.status).font(.caption).lineLimit(2)
                Spacer()
                Button("关闭") { preview.stop() }
            }.padding(8)
        }
    }
}
