import AppKit
import Combine
import Darwin
import SwiftUI
import TrackpadBridge

@main
struct TabPadApp: App {
    @StateObject private var controller = DriverController()
    var body: some Scene {
        WindowGroup("TabPad") {
            ContentView().environmentObject(controller)
                .frame(minWidth: 520, minHeight: 660)
                .onAppear { controller.start() }
        }
    }
}

@MainActor
final class DriverController: ObservableObject {
    enum AreaUnit: String, CaseIterable, Identifiable { case percent = "Percent", millimeters = "Millimeters"; var id: Self { self } }
    enum Axis { case horizontal, vertical }
    enum AspectBasis { case width, height }
    struct Display: Identifiable, Hashable { let id: CGDirectDisplayID; let name: String; let frame: CGRect }

    @Published var active = false { didSet { apply() } }
    @Published var inputFilteringEnabled = true { didSet { apply() } }
    @Published var displays: [Display] = []
    @Published var selectedDisplayID: CGDirectDisplayID = CGMainDisplayID() { didSet { apply() } }
    // Stored normalized internally; converted to the selected entry unit in the UI.
    @Published var areaX = 0.0 { didSet { saveArea(); apply() } }
    @Published var areaY = 0.0 { didSet { saveArea(); apply() } }
    @Published var areaWidth = 1.0 { didSet { saveArea(); apply() } }
    @Published var areaHeight = 1.0 { didSet { saveArea(); apply() } }
    @Published var areaUnit: AreaUnit = .percent
    @Published var aspectLocked = false { didSet { if aspectLocked { applyAspectRatio(basis: .width) } } }
    @Published var aspectRatioText = "1:1" { didSet { if aspectLocked { applyAspectRatio(basis: .width) } } }
    @Published var aspectRatioMessage = ""
    @Published var invertX = false { didSet { apply() } }
    @Published var invertY = true { didSet { apply() } }
    @Published var status = "Starting…"
    @Published var accessibilityGranted = false
    @Published var sensorWidthMM = 0.0
    @Published var sensorHeightMM = 0.0
    @Published var fingerX = 0.0
    @Published var fingerY = 0.0
    @Published var fingerPresent = false
    @Published var areaSaveStatus = "No saved area yet"
    @Published var macModel = "Detecting Mac…"
    @Published var connectedTrackpads = "Detecting trackpad…"
    private var driverStarted = false
    private struct SavedArea: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    private static let savedAreaURL: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TabPad", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("area.json")
    }()

    var sensorAvailable: Bool { sensorWidthMM > 0 && sensorHeightMM > 0 }

    init() {
        let saved = Self.loadSavedArea()
        areaX = saved?.x ?? 0
        areaY = saved?.y ?? 0
        areaWidth = saved?.width ?? 1
        areaHeight = saved?.height ?? 1
        setArea(x: areaX, y: areaY, width: areaWidth, height: areaHeight)
    }

    func start() {
        refreshDisplays()
        refreshHardware()
        requestAccessibility()
    }

    func requestAccessibility() {
        let trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        updateAccessibilityState(trusted)
    }

    func checkAccessibilityPermission() {
        updateAccessibilityState(AXIsProcessTrusted())
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func updateAccessibilityState(_ trusted: Bool) {
        accessibilityGranted = trusted
        guard trusted else {
            status = "Accessibility permission is required. Turn on this exact TabPad app in System Settings."
            return
        }
        guard !driverStarted else { return }
        driverStarted = APStart()
        status = driverStarted ? "Ready — tablet mode is off" : String(cString: APLastError())
        if driverStarted { refreshTrackpadState() }
    }

    func refreshDisplays() {
        displays = NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(number.uint32Value)
            return Display(id: id, name: screen.localizedName, frame: CGDisplayBounds(id))
        }
        if !displays.contains(where: { $0.id == selectedDisplayID }), let first = displays.first { selectedDisplayID = first.id }
    }

    func refreshTrackpadState() {
        var width = 0.0, height = 0.0, x = 0.0, y = 0.0, present = false
        _ = APGetSensorDimensions(&width, &height)
        APGetCurrentFinger(&x, &y, &present)
        sensorWidthMM = width; sensorHeightMM = height
        // MultitouchSupport reports its physical Y axis bottom-to-top; SwiftUI's
        // editor is top-to-bottom. Flip only the diagnostic display coordinate.
        fingerX = x; fingerY = 1 - y; fingerPresent = present
    }

    func refreshHardware() {
        macModel = Self.readMacModel()
        var devices = [CChar](repeating: 0, count: 512)
        APGetConnectedTrackpads(&devices, devices.count)
        connectedTrackpads = String(decoding: devices.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func readMacModel() -> String {
        var size: size_t = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Unknown Mac" }
        var bytes = [CChar](repeating: 0, count: Int(size))
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "Unknown Mac" }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    func resetArea() { setArea(x: 0, y: 0, width: 1, height: 1) }
    func centerArea() {
        setArea(x: (1 - areaWidth) / 2, y: (1 - areaHeight) / 2, width: areaWidth, height: areaHeight)
    }
    func setArea(x: Double, y: Double, width: Double, height: Double, aspectBasis: AspectBasis? = nil) {
        var requestedWidth = width, requestedHeight = height
        if aspectLocked, let aspectBasis, let ratio = parsedAspectRatio {
            let horizontalMM = dimension(for: .horizontal), verticalMM = dimension(for: .vertical)
            switch aspectBasis {
            case .width:
                requestedHeight = requestedWidth * horizontalMM / (ratio * verticalMM)
            case .height:
                requestedWidth = requestedHeight * ratio * verticalMM / horizontalMM
            }
        }
        var safeWidth = max(0.0001, requestedWidth), safeHeight = max(0.0001, requestedHeight)
        let requestedX = min(1, max(0, x)), requestedY = min(1, max(0, y))
        // Scale the whole rectangle when an aspect-locked edit would exceed the
        // usable trackpad, rather than independently clipping one dimension.
        if aspectLocked, aspectBasis != nil {
            let scale = min(1, (1 - requestedX) / safeWidth, (1 - requestedY) / safeHeight)
            safeWidth *= max(0, scale)
            safeHeight *= max(0, scale)
        }
        safeWidth = min(1, safeWidth); safeHeight = min(1, safeHeight)
        areaX = min(1 - safeWidth, requestedX); areaY = min(1 - safeHeight, requestedY)
        areaWidth = safeWidth; areaHeight = safeHeight
    }

    func binding(for keyPath: ReferenceWritableKeyPath<DriverController, Double>, axis: Axis) -> Binding<Double> {
        Binding(get: { [weak self] in
            guard let self else { return 0 }
            return self[keyPath: keyPath] * self.inputScale(for: axis)
        }, set: { [weak self] newValue in
            guard let self else { return }
            let scale = self.inputScale(for: axis)
            guard scale > 0 else { return }
            let normalized = min(1, max(0, newValue / scale))
            if keyPath == \.areaWidth {
                self.setArea(x: self.areaX, y: self.areaY, width: normalized, height: self.areaHeight, aspectBasis: .width)
            } else if keyPath == \.areaHeight {
                self.setArea(x: self.areaX, y: self.areaY, width: self.areaWidth, height: normalized, aspectBasis: .height)
            } else {
                self[keyPath: keyPath] = normalized
            }
        })
    }

    func dimension(for axis: Axis) -> Double {
        switch axis { case .horizontal: return sensorAvailable ? sensorWidthMM : 100; case .vertical: return sensorAvailable ? sensorHeightMM : 100 }
    }

    func inputScale(for axis: Axis) -> Double {
        areaUnit == .percent ? 100 : dimension(for: axis)
    }

    private var parsedAspectRatio: Double? {
        let normalized = aspectRatioText.replacingOccurrences(of: " ", with: "")
        let parts = normalized.split(whereSeparator: { $0 == ":" || $0 == "/" })
        if parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]), width > 0, height > 0 {
            return width / height
        }
        if let ratio = Double(normalized), ratio > 0 { return ratio }
        return nil
    }

    private func applyAspectRatio(basis: AspectBasis) {
        guard parsedAspectRatio != nil else {
            aspectRatioMessage = "Enter a ratio such as 1:1 or 9:16."
            return
        }
        aspectRatioMessage = ""
        setArea(x: areaX, y: areaY, width: areaWidth, height: areaHeight, aspectBasis: basis)
    }

    private func saveArea() {
        let area = SavedArea(x: areaX, y: areaY, width: areaWidth, height: areaHeight)
        do {
            let data = try JSONEncoder().encode(area)
            try data.write(to: Self.savedAreaURL, options: .atomic)
            areaSaveStatus = "Area saved"
        } catch {
            areaSaveStatus = "Could not save area: \(error.localizedDescription)"
        }
    }

    private static func loadSavedArea() -> SavedArea? {
        guard let data = try? Data(contentsOf: savedAreaURL) else { return nil }
        return try? JSONDecoder().decode(SavedArea.self, from: data)
    }

    private func apply() {
        guard let display = displays.first(where: { $0.id == selectedDisplayID }) else { return }
        APSetMapping(display.frame.origin.x, display.frame.origin.y, display.frame.width, display.frame.height,
                     areaX, areaY, areaWidth, areaHeight, invertX, invertY)
        APSetFiltering(inputFilteringEnabled)
        APSetEnabled(active)
        if status == "Ready — tablet mode is off" || status == "Tablet mode is on" { status = active ? "Tablet mode is on" : "Ready — tablet mode is off" }
    }
}

struct ContentView: View {
    @EnvironmentObject private var controller: DriverController
    // The preview is only for the TabPad window. Keep it out of the gameplay
    // path: touch input continues in the C bridge while lazer is frontmost.
    private let monitor = Timer.publish(every: 1.0 / 20.0, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Status") {
                Text(controller.status).foregroundStyle(controller.active ? .green : .secondary)
                if !controller.accessibilityGranted {
                    HStack {
                        Button("Open Accessibility Settings") { controller.openAccessibilitySettings() }
                        Button("Check again") { controller.checkAccessibilityPermission() }
                    }
                    Text("After enabling it, return here—the app will detect the change automatically.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Toggle("Enable absolute tablet mode", isOn: $controller.active)
                    .font(.title3.weight(.semibold))
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .disabled(!controller.accessibilityGranted || (!controller.status.hasPrefix("Ready") && !controller.status.hasPrefix("Tablet")))
                Toggle("Input filtering", isOn: $controller.inputFilteringEnabled)
                Text(controller.inputFilteringEnabled ? "Micro-shake filtering is on; output is capped at 240 Hz." : "Raw low-latency mode is on; every trackpad contact is sent immediately.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("osu!lazer compatibility") {
                Text("TabPad now sends absolute mouse-move events that lazer can receive. In osu!lazer Settings → Input, turn High Precision Mouse off and Tablet input off; TabPad presents itself as a mouse, not a native tablet.")
                    .font(.footnote)
                Text("A tiny no-lag dead-zone rejects sub-pixel shake; meaningful movements always map directly to the cursor.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Target display") {
                Picker("Display", selection: $controller.selectedDisplayID) {
                    ForEach(controller.displays) { display in Text("\(display.name) — \(Int(display.frame.width)) × \(Int(display.frame.height))").tag(display.id) }
                }
                Button("Refresh displays") { controller.refreshDisplays() }
            }
            Section("Detected hardware") {
                LabeledContent("Mac model", value: controller.macModel)
                LabeledContent("Connected trackpad(s)", value: controller.connectedTrackpads)
                Button("Refresh hardware") { controller.refreshHardware() }
                Text("TabPad is macOS-only. It listens to all detected Apple multitouch trackpads, including wireless Magic Trackpads. The physical-size reading updates to the trackpad you touch.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Trackpad area") {
                Picker("Unit", selection: $controller.areaUnit) {
                    ForEach(DriverController.AreaUnit.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                if controller.areaUnit == .millimeters && !controller.sensorAvailable {
                    Text("Physical dimensions are unavailable on this trackpad; use Percent mode.").font(.footnote).foregroundStyle(.orange)
                }
                AreaEditor(controller: controller).frame(height: 220)
                HStack {
                    AdaptiveNumberField(label: "Left", value: controller.binding(for: \.areaX, axis: .horizontal), maximum: (1 - controller.areaWidth) * controller.inputScale(for: .horizontal), allowsZero: true, suffix: controller.areaUnit == .percent ? "%" : "mm")
                    AdaptiveNumberField(label: "Top", value: controller.binding(for: \.areaY, axis: .vertical), maximum: (1 - controller.areaHeight) * controller.inputScale(for: .vertical), allowsZero: true, suffix: controller.areaUnit == .percent ? "%" : "mm")
                }
                HStack {
                    AdaptiveNumberField(label: "Width", value: controller.binding(for: \.areaWidth, axis: .horizontal), maximum: controller.inputScale(for: .horizontal), suffix: controller.areaUnit == .percent ? "%" : "mm")
                    AdaptiveNumberField(label: "Height", value: controller.binding(for: \.areaHeight, axis: .vertical), maximum: controller.inputScale(for: .vertical), suffix: controller.areaUnit == .percent ? "%" : "mm")
                }
                HStack {
                    Toggle("Lock aspect ratio", isOn: $controller.aspectLocked)
                        .toggleStyle(.button)
                    TextField("1:1", text: $controller.aspectRatioText)
                        .textFieldStyle(.roundedBorder).frame(width: 90)
                        .multilineTextAlignment(.center)
                }
                if !controller.aspectRatioMessage.isEmpty {
                    Text(controller.aspectRatioMessage).font(.footnote).foregroundStyle(.orange)
                }
                HStack {
                    Button("Center area") { controller.centerArea() }
                    Button("Use full trackpad") { controller.resetArea() }
                }
                Text(controller.areaSaveStatus).font(.footnote).foregroundStyle(.secondary)
                if controller.sensorAvailable { Text("Trackpad sensor: \(Int(controller.sensorWidthMM.rounded())) × \(Int(controller.sensorHeightMM.rounded())) mm").font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Orientation") {
                Toggle("Mirror horizontally", isOn: $controller.invertX)
                Toggle("Invert vertical axis", isOn: $controller.invertY)
            }
            Section {
                Text("The green dot is the live one-finger contact. Drag the blue region to reposition it; drag a corner handle to resize. Keyboard keys remain best for osu! clicks.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding()
        .onReceive(monitor) { _ in
            if NSApp.isActive { controller.refreshTrackpadState() }
            if !controller.accessibilityGranted { controller.checkAccessibilityPermission() }
        }
    }
}

private struct AdaptiveNumberField: View {
    let label: String
    @Binding var value: Double
    let maximum: Double
    var allowsZero = false
    let suffix: String
    @State private var text = ""
    @FocusState private var focused: Bool

    private var fieldWidth: CGFloat {
        min(220, max(110, CGFloat(text.count) * 10 + 54))
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label).frame(width: 45, alignment: .leading)
            TextField(label, text: $text)
                .textFieldStyle(.roundedBorder).frame(width: fieldWidth).multilineTextAlignment(.trailing)
                .focused($focused)
                .onAppear { text = formatted(value) }
                .onChange(of: value) { newValue in if !focused { text = formatted(newValue) } }
                .onChange(of: text) { newText in updateValue(from: newText) }
                .onSubmit { normalise() }
                .onChange(of: focused) { isFocused in if !isFocused { normalise() } }
            Text(suffix).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Enter \(allowsZero ? "zero or" : "a") positive number up to \(formatted(maximum)) \(suffix).")
    }

    private func updateValue(from input: String) {
        guard let candidate = Double(input), candidate.isFinite, candidate <= maximum, candidate >= 0 else { return }
        guard allowsZero || candidate > 0 else { return }
        value = candidate
    }

    private func normalise() {
        guard let candidate = Double(text), candidate.isFinite, candidate <= maximum, candidate >= 0, allowsZero || candidate > 0 else {
            text = formatted(value)
            return
        }
        value = candidate
        text = formatted(candidate)
    }

    private func formatted(_ number: Double) -> String {
        number.formatted(.number.precision(.fractionLength(0...3)))
    }
}

private struct AreaEditor: View {
    @ObservedObject var controller: DriverController
    @State private var moveOrigin: CGRect?
    @State private var resizeOrigin: CGRect?
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let rect = CGRect(x: controller.areaX * size.width, y: controller.areaY * size.height, width: controller.areaWidth * size.width, height: controller.areaHeight * size.height)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                PadGrid().stroke(.secondary.opacity(0.22), lineWidth: 0.5)
                Rectangle().path(in: rect).fill(.blue.opacity(0.22))
                Rectangle().path(in: rect).stroke(.blue, lineWidth: 2).contentShape(Rectangle()).gesture(moveGesture(in: size))
                if controller.fingerPresent {
                    Circle().fill(.green).overlay(Circle().stroke(.white, lineWidth: 2)).frame(width: 14, height: 14)
                        .position(x: controller.fingerX * size.width, y: controller.fingerY * size.height)
                }
                ForEach(Corner.allCases) { corner in
                    Circle().fill(.white).overlay(Circle().stroke(.blue, lineWidth: 2)).frame(width: 14, height: 14)
                        .position(corner.point(in: rect)).gesture(resizeGesture(corner: corner, in: size))
                }
            }.clipShape(RoundedRectangle(cornerRadius: 10))
        }.accessibilityLabel("Interactive trackpad area editor")
    }

    private func moveGesture(in size: CGSize) -> some Gesture {
        DragGesture().onChanged { value in
            if moveOrigin == nil { moveOrigin = CGRect(x: controller.areaX, y: controller.areaY, width: controller.areaWidth, height: controller.areaHeight) }
            guard let origin = moveOrigin else { return }
            controller.setArea(x: origin.origin.x + value.translation.width / size.width, y: origin.origin.y + value.translation.height / size.height, width: origin.width, height: origin.height)
        }.onEnded { _ in moveOrigin = nil }
    }
    private func resizeGesture(corner: Corner, in size: CGSize) -> some Gesture {
        DragGesture().onChanged { value in
            if resizeOrigin == nil { resizeOrigin = CGRect(x: controller.areaX, y: controller.areaY, width: controller.areaWidth, height: controller.areaHeight) }
            guard let origin = resizeOrigin else { return }
            let dx = value.translation.width / size.width, dy = value.translation.height / size.height
            var x = origin.origin.x, y = origin.origin.y, width = origin.width, height = origin.height
            if corner.isLeft { x += dx; width -= dx } else { width += dx }
            if corner.isTop { y += dy; height -= dy } else { height += dy }
            let basis: DriverController.AspectBasis = abs(dx) >= abs(dy) ? .width : .height
            controller.setArea(x: x, y: y, width: width, height: height, aspectBasis: basis)
        }.onEnded { _ in resizeOrigin = nil }
    }
    private enum Corner: CaseIterable, Identifiable {
        case topLeft, topRight, bottomLeft, bottomRight
        var id: Self { self }
        var isLeft: Bool { self == .topLeft || self == .bottomLeft }
        var isTop: Bool { self == .topLeft || self == .topRight }
        func point(in rect: CGRect) -> CGPoint { CGPoint(x: isLeft ? rect.minX : rect.maxX, y: isTop ? rect.minY : rect.maxY) }
    }
}

private struct PadGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 1..<10 {
            let fraction = CGFloat(index) / 10
            path.move(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * fraction))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * fraction))
        }
        return path
    }
}
