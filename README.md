# ax-recorder

Record iOS Simulator UI interactions and export them as structured event logs — perfect for generating E2E tests with AI.

## How it works

You run `ax-recorder`, click around in the iOS Simulator, press Ctrl+C and get a structured log of every tap, focus, text change etc. with `testID` / accessibility identifiers. Feed that log to an AI agent and ask it to write an E2E test.

```
14:23:11.042  [focus]        id=emailInput    role=AXTextField  label="Email"
14:23:11.891  [valueChanged] id=emailInput    role=AXTextField  label="Email"
14:23:14.203  [tap]          id=loginButton   role=AXButton     label="Zaloguj"
14:23:15.110  [focus]        id=homeScreen    role=AXOther
```

No WebDriver. No Appium. No Detox runner. Just macOS Accessibility API.

---

## Install

### Homebrew (recommended)

```bash
brew tap CodeLionApps/ax-recorder
brew install ax-recorder
```

### From source

```bash
git clone https://github.com/CodeLionApps/ax-recorder
cd ax-recorder
./install.sh
```

---

## Setup (one-time)

Grant Accessibility permission to your terminal app:

**System Settings → Privacy & Security → Accessibility → add Terminal** (or iTerm2, Warp, etc.)

---

## Usage

```bash
# Auto-detect running simulator
ax-recorder

# Save log to JSON file
ax-recorder -o session.json

# List running simulators (if you have multiple)
ax-recorder --list

# Target specific simulator by PID
ax-recorder --pid 12345
```

Press **Ctrl+C** to stop recording. If no `-o` flag is given, JSON is printed to stdout.

---

## JSON output format

```json
[
  {
    "timestamp": "14:23:11.042",
    "action": "focus",
    "testID": "emailInput",
    "role": "AXTextField",
    "label": "Email"
  },
  {
    "timestamp": "14:23:14.203",
    "action": "tap",
    "testID": "loginButton",
    "role": "AXButton",
    "label": "Zaloguj"
  }
]
```

### Action types

| Action         | Trigger                |
| -------------- | ---------------------- |
| `tap`          | Button press / tap     |
| `focus`        | Element focused        |
| `valueChanged` | Input value changed    |
| `textChanged`  | Text selection changed |
| `menuSelect`   | Menu item selected     |
| `scroll`       | Scrolled to element    |

---

## AI workflow

```
1. ax-recorder -o session.json   # nagraj sesję
2. Wrzuć session.json do agenta
3. "Na podstawie tych kroków napisz test E2E w Detox / Playwright / Appium"
```

---

## Requirements

- macOS 13+
- Xcode Command Line Tools
- iOS Simulator (Simulator.app)

---

## License

MIT
