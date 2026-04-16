import Cocoa
import ApplicationServices

// MARK: - Config

let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

var eventLog: [[String: String]] = []
var observer: AXObserver?
let axPressedNotification = "AXPressed"
let axScrolledToVisibleNotification = "AXScrolledToVisible"

// MARK: - Helpers

func timestamp() -> String {
    dateFormatter.string(from: Date())
}

func getAttr(_ element: AXUIElement, _ attr: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success else {
        return nil
    }
    return value as? String
}

func getIdentifier(_ element: AXUIElement) -> String {
    if let id = getAttr(element, kAXIdentifierAttribute) { return id }
    if let label = getAttr(element, kAXDescriptionAttribute) { return "label:\(label)" }
    if let title = getAttr(element, kAXTitleAttribute) { return "title:\(title)" }
    if let value = getAttr(element, kAXValueAttribute) { return "value:\(value)" }
    return "<unknown>"
}

func getRole(_ element: AXUIElement) -> String {
    return getAttr(element, kAXRoleAttribute) ?? "unknown"
}

func getLabel(_ element: AXUIElement) -> String {
    return getAttr(element, kAXDescriptionAttribute)
        ?? getAttr(element, kAXLabelValueAttribute)
        ?? getAttr(element, kAXTitleAttribute)
        ?? getAttr(element, kAXValueAttribute)
        ?? ""
}

// MARK: - Event callback

let axCallback: AXObserverCallback = { _, element, notification, _ in
    let notif = notification as String

    let actionMap: [String: String] = [
        axPressedNotification:          "tap",
        kAXFocusedUIElementChangedNotification: "focus",
        kAXValueChangedNotification:     "valueChanged",
        kAXSelectedTextChangedNotification: "textChanged",
        kAXMenuItemSelectedNotification: "menuSelect",
        axScrolledToVisibleNotification: "scroll",
    ]

    guard let action = actionMap[notif] else { return }

    let id    = getIdentifier(element)
    let role  = getRole(element)
    let label = getLabel(element)
    let ts    = timestamp()

    var parts = ["\(ts)  [\(action)]  id=\(id)  role=\(role)"]
    if !label.isEmpty { parts.append("label=\"\(label)\"") }
    let line = parts.joined(separator: "  ")

    print(line)
    fflush(stdout)

    eventLog.append([
        "timestamp": ts,
        "action": action,
        "testID": id,
        "role": role,
        "label": label,
    ])
}

// MARK: - Simulator discovery

func findSimulator(named hint: String? = nil) -> NSRunningApplication? {
    let apps = NSWorkspace.shared.runningApplications
    let sims = apps.filter { $0.localizedName == "Simulator" }

    if sims.isEmpty { return nil }
    if sims.count == 1 { return sims[0] }

    if hint != nil {
        // można by tu matchować po tytule okna, ale PID wystarczy do AX
        print("⚠️  Znaleziono \(sims.count) symulatory, biorę pierwszy. Użyj --pid <pid> żeby wybrać konkretny.")
    }

    return sims[0]
}

// MARK: - Subscribe to events

let notificationsToWatch = [
    axPressedNotification,
    kAXFocusedUIElementChangedNotification,
    kAXValueChangedNotification,
    kAXSelectedTextChangedNotification,
    kAXMenuItemSelectedNotification,
    axScrolledToVisibleNotification,
]

func subscribeRecursively(_ observer: AXObserver, _ element: AXUIElement, depth: Int = 0) {
    guard depth < 10 else { return }

    for notif in notificationsToWatch {
        AXObserverAddNotification(observer, element, notif as CFString, nil)
    }

    var childrenRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
          let children = childrenRef as? [AXUIElement] else { return }

    for child in children {
        subscribeRecursively(observer, child, depth: depth + 1)
    }
}

// MARK: - JSON export

func exportJSON() {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    if let data = try? encoder.encode(eventLog.map { $0 }),
       let json = String(data: data, encoding: .utf8) {
        print("\n--- JSON LOG ---")
        print(json)
    }
}

func saveJSON(to path: String) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    if let data = try? encoder.encode(eventLog.map { $0 }) {
        try? data.write(to: URL(fileURLWithPath: path))
        print("💾  Zapisano log do: \(path)")
    }
}

// MARK: - Main

// Parsuj argumenty
var targetPID: pid_t? = nil
var outputPath: String? = nil
var listMode = false

var args = CommandLine.arguments.dropFirst()
while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--list":
        listMode = true
    case "--pid":
        if let next = args.first, let pid = pid_t(next) {
            targetPID = pid
            args.removeFirst()
        }
    case "--output", "-o":
        if let next = args.first {
            outputPath = next
            args.removeFirst()
        }
    default:
        break
    }
}

// Tryb listowania
if listMode {
    let sims = NSWorkspace.shared.runningApplications.filter { $0.localizedName == "Simulator" }
    if sims.isEmpty {
        print("❌  Brak uruchomionych symulatorów.")
    } else {
        print("Uruchomione symulatory:")
        for s in sims {
            print("  PID \(s.processIdentifier)")
        }
    }
    exit(0)
}

// Znajdź symulator
let simApp: NSRunningApplication
if let pid = targetPID {
    guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid }) else {
        print("❌  Nie znaleziono procesu o PID \(pid)")
        exit(1)
    }
    simApp = app
} else {
    guard let app = findSimulator() else {
        print("❌  Nie znaleziono uruchomionego Simulator.app. Odpal symulator najpierw.")
        exit(1)
    }
    simApp = app
}

print("🎯  Podpięto pod Simulator (PID \(simApp.processIdentifier))")
print("📋  Nagrywanie eventów... (Ctrl+C żeby zakończyć)\n")

// Sprawdź uprawnienia Accessibility
let trusted = AXIsProcessTrusted()
if !trusted {
    print("⚠️  Brak uprawnień Accessibility!")
    print("   Przejdź do: System Settings → Privacy & Security → Accessibility")
    print("   i dodaj Terminal (lub iTerm2).\n")
}

// Utwórz observer
let pid = simApp.processIdentifier
let appElement = AXUIElementCreateApplication(pid)

AXObserverCreate(pid, axCallback, &observer)
guard let obs = observer else {
    print("❌  Nie udało się utworzyć AXObserver")
    exit(1)
}

subscribeRecursively(obs, appElement)
CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)

// Obsługa Ctrl+C
signal(SIGINT) { _ in
    print("\n\n✅  Zakończono nagrywanie. Zebrano \(eventLog.count) eventów.\n")
    if let path = outputPath {
        saveJSON(to: path)
    } else {
        exportJSON()
    }
    exit(0)
}

// Uruchom pętlę
CFRunLoopRun()
