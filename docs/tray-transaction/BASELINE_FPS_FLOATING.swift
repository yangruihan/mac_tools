import SwiftUI

struct PreviewPaused: LocalizedError {
    var errorDescription: String? { "源窗口暂不可见" }
}

// A single in-flight capture and a single displayed image: no frame backlog or recordings.
final class FloatingPreview: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var image: CGImage?
    @Published private(set) var status = "尚未开始预览"
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    private(set) var panel: NSPanel?
    private var captureTask: Task<Void, Never>?
    private var generation = UUID()

    static func pixelSize(for size: CGSize) -> CGSize {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return CGSize(width: 640, height: 400) }
        let scale = min(2, 1600 / max(size.width, size.height))
        return CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
    }

    func begin(title: String, showPanel: Bool = true, capture: @escaping () async throws -> CGImage) {
        stop()
        let token = generation
        status = "等待画面…"; isRunning = true; isPaused = false
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
        // ponytail: monitoring preview at up to 5 fps / 1600px; use SCStream if smooth video is needed.
        captureTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    let frame = try await capture()
                    guard !Task.isCancelled, let self, self.generation == token else { return }
                    self.image = frame; self.isPaused = false
                    self.status = "只读预览 · 拖动边框调整大小"
                    try await Task.sleep(nanoseconds: 200_000_000)
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

    func stop() {
        generation = UUID()
        captureTask?.cancel(); captureTask = nil
        image = nil; isRunning = false; isPaused = false; status = "尚未开始预览"
        panel?.delegate = nil
        panel?.contentView = nil
        panel?.close(); panel = nil
    }
    func windowWillClose(_ notification: Notification) { stop() }
    deinit { captureTask?.cancel() }
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
