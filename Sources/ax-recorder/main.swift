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
let maxInitialTraversalDepth = 24
let maxInitialTraversalNodes = 6_000

let notificationsToWatch: [String] = [
    axPressedNotification,
    kAXFocusedUIElementChangedNotification as String,
    kAXValueChangedNotification as String,
    kAXSelectedTextChangedNotification as String,
    kAXMenuItemSelectedNotification as String,
    axScrolledToVisibleNotification,
]

let arrayAttributesToTraverse: [String] = [
    kAXChildrenAttribute as String,
    kAXVisibleChildrenAttribute as String,
    kAXWindowsAttribute as String,
    "AXContents",
]

let singleAttributesToTraverse: [String] = [
    kAXMainWindowAttribute as String,
    kAXFocusedWindowAttribute as String,
    kAXFocusedUIElementAttribute as String,
]

var subscribedNotificationKeys = Set<String>()
var seenElements = Set<Int>()
var registrationErrors: [String: Int] = [:]

// MARK: - Helpers

func timestamp() -> String {
    dateFormatter.string(from: Date())
}

func copyAttr(_ element: AXUIElement, _ attr: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success else {
        return nil
    }
    return value
}

func getAttr(_ element: AXUIElement, _ attr: String) -> String? {
    copyAttr(element, attr) as? String
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

func elementHash(_ element: AXUIElement) -> Int {
    Int(CFHash(element))
}

func registrationErrorKey(_ error: AXError) -> String {
    switch error {
    case .apiDisabled:
        return "apiDisabled"
    case .cannotComplete:
        return "cannotComplete"
    case .invalidUIElement:
        return "invalidUIElement"
    case .invalidUIElementObserver:
        return "invalidObserver"
    case .notificationUnsupported:
        return "notificationUnsupported"
    case .notificationAlreadyRegistered:
        return "alreadyRegistered"
    default:
        return "axError(\(error.rawValue))"
    }
}

func addNotification(_ observer: AXObserver, _ element: AXUIElement, _ notification: String) -> Bool {
    let key = "\(elementHash(element))::\(notification)"
    guard !subscribedNotificationKeys.contains(key) else { return false }

    let result = AXObserverAddNotification(observer, element, notification as CFString, nil)
    switch result {
    case .success:
        subscribedNotificationKeys.insert(key)
        return true
    case .notificationAlreadyRegistered:
        subscribedNotificationKeys.insert(key)
        return false
    case .notificationUnsupported:
        return false
    default:
        let errKey = registrationErrorKey(result)
        registrationErrors[errKey, default: 0] += 1
        return false
    }
}

func isAXUIElementRef(_ value: CFTypeRef) -> Bool {
    CFGetTypeID(value) == AXUIElementGetTypeID()
}

func extractElements(from value: CFTypeRef) -> [AXUIElement] {
    if isAXUIElementRef(value) {
        return [unsafeBitCast(value, to: AXUIElement.self)]
    }

    guard let values = value as? [AnyObject] else { return [] }
    var result: [AXUIElement] = []
    for item in values {
        let ref = item as CFTypeRef
        if isAXUIElementRef(ref) {
            result.append(unsafeBitCast(ref, to: AXUIElement.self))
        }
    }
    return result
}

func relatedElements(of element: AXUIElement) -> [AXUIElement] {
    var result: [AXUIElement] = []

    for attr in arrayAttributesToTraverse {
        guard let value = copyAttr(element, attr) else { continue }
        result.append(contentsOf: extractElements(from: value))
    }

    for attr in singleAttributesToTraverse {
        guard let value = copyAttr(element, attr) else { continue }
        result.append(contentsOf: extractElements(from: value))
    }

    return result
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

    // Simulator dynamicznie podmienia poddrzewa AX. Doprofiluj subskrypcje
    // po każdym realnym zdarzeniu, żeby nie zgubić dalszych eventów.
    if let obs = observer {
        _ = addNotification(obs, element, axPressedNotification)
        _ = addNotification(obs, element, kAXValueChangedNotification as String)
        for related in relatedElements(of: element) {
            _ = addNotification(obs, related, axPressedNotification)
            _ = addNotification(obs, related, kAXValueChangedNotification as String)
        }
    }
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

@discardableResult
func subscribeRecursively(
    _ observer: AXObserver,
    _ root: AXUIElement,
    maxDepth: Int = maxInitialTraversalDepth,
    maxNodes: Int = maxInitialTraversalNodes
) -> (visited: Int, added: Int) {
    var queue: [(AXUIElement, Int)] = [(root, 0)]
    var localVisited = 0
    var localAdded = 0

    while !queue.isEmpty && localVisited < maxNodes {
        let (element, depth) = queue.removeFirst()
        let elementID = elementHash(element)
        if seenElements.contains(elementID) && depth > 0 {
            continue
        }

        seenElements.insert(elementID)
        localVisited += 1

        for notif in notificationsToWatch {
            if addNotification(observer, element, notif) {
                localAdded += 1
            }
        }

        guard depth < maxDepth else { continue }
        let next = relatedElements(of: element)
        for child in next {
            queue.append((child, depth + 1))
        }
    }

    return (localVisited, localAdded)
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
let trustOpts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
let trusted = AXIsProcessTrustedWithOptions(trustOpts)
if !trusted {
    print("❌  Brak uprawnień Accessibility!")
    print("   Przejdź do: System Settings → Privacy & Security → Accessibility")
    print("   i dodaj Terminal (lub iTerm2), potem uruchom ponownie.\n")
    exit(1)
}

// Utwórz observer
let pid = simApp.processIdentifier
let appElement = AXUIElementCreateApplication(pid)

let observerCreateResult = AXObserverCreate(pid, axCallback, &observer)
if observerCreateResult != .success {
    print("❌  Nie udało się utworzyć AXObserver: \(registrationErrorKey(observerCreateResult))")
    exit(1)
}

guard let obs = observer else {
    print("❌  Nie udało się utworzyć AXObserver")
    exit(1)
}

let initial = subscribeRecursively(obs, appElement)
print("🔎  AX init: odwiedzono \(initial.visited) elementów, aktywnych subskrypcji: \(initial.added)")
if initial.added == 0 {
    print("⚠️  Nie udało się zarejestrować żadnej subskrypcji AX.")
}
if !registrationErrors.isEmpty {
    let summary = registrationErrors
        .sorted { $0.value > $1.value }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: ", ")
    print("ℹ️  Rejestracja AX (diag): \(summary)")
}

CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)

// Simulator często dynamicznie tworzy/podmienia poddrzewa AX.
// Okresowe dosubskrybowanie zapobiega "ciszy" po zmianie widoku.
Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
    let rescan = subscribeRecursively(obs, appElement, maxDepth: 8, maxNodes: 1_500)
    if rescan.added > 0 {
        print("🔁  AX rescan: +\(rescan.added) nowych subskrypcji")
        fflush(stdout)
    }
}

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
