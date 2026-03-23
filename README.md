# Digitex POS — Windows Desktop Application

Flutter Windows desktop wrapper for the Digitex POS web application.  
Loads the SaaS POS (*.digitex.uz) in a WebView2, receives print commands from the Vue frontend via `postMessage`, and sends ESC/POS commands to LAN thermal printers over TCP socket.

---

## Architecture

```
┌──────────────────────────────────────────────────┐
│              Flutter Windows App                  │
│                                                   │
│  ┌────────────────────────────────────────────┐   │
│  │          WebView2 (webview_windows)         │   │
│  │                                             │   │
│  │   Vue POS App (https://*.digitex.uz)        │   │
│  │                                             │   │
│  │   postMessage({ type: "PRINT", data: ... }) │   │
│  └──────────────┬─────────────────────────────┘   │
│                 │                                  │
│    onWebMessage │                                  │
│                 ▼                                  │
│  ┌──────────────────────────┐                     │
│  │     PrinterService       │                     │
│  │  ┌───────────────────┐   │                     │
│  │  │  EscPosBuilder    │   │                     │
│  │  │  (CP866 encoding) │   │                     │
│  │  └───────────────────┘   │                     │
│  └──────────┬───────────────┘                     │
│             │ TCP Socket                           │
│             ▼                                      │
│     192.168.x.x:9100                              │
│     (Thermal Printer)                             │
└──────────────────────────────────────────────────┘
```

### Message Flow

1. User clicks "Print" in the POS web app
2. Vue detects WebView2 environment via `isDesktopApp()`
3. Vue sends `postMessage({ type: "PRINT", data: receiptData })`
4. Flutter receives the message in `HomeScreen._onWebMessage()`
5. `PrinterService.printReceipt()` builds ESC/POS byte buffer
6. Raw bytes sent to printer via TCP socket (port 9100)
7. Flutter sends `{ type: "PRINT_RESULT", success: true }` back to Vue
8. Vue shows success/error toast

---

## Project Structure

```
desktopapp/
├── lib/
│   ├── main.dart                    # Entry point, window setup
│   ├── app.dart                     # MaterialApp, theme
│   ├── models/
│   │   ├── printer_config.dart      # Printer settings model
│   │   └── receipt_data.dart        # Receipt JSON model (matches backend)
│   ├── screens/
│   │   ├── home_screen.dart         # WebView + message listener
│   │   └── settings_screen.dart     # Printer/URL config UI
│   ├── services/
│   │   ├── printer_service.dart     # TCP socket ESC/POS printing
│   │   └── settings_service.dart    # SharedPreferences persistence
│   └── utils/
│       └── esc_pos_commands.dart    # ESC/POS byte command builder
├── windows/                         # Windows runner (C++)
├── pubspec.yaml
└── README.md
```

---

## Prerequisites

### Development Machine (any OS for code editing, Windows required for building)

1. **Flutter SDK** >= 3.19  
   ```bash
   flutter --version
   ```

2. **Visual Studio 2022** with the following workloads:
   - "Desktop development with C++"
   - Windows SDK (10.0.x or later)

3. **WebView2 Runtime** — pre-installed on Windows 10/11. For older systems:
   - Download: https://developer.microsoft.com/en-us/microsoft-edge/webview2/

4. Verify Windows desktop is enabled:
   ```bash
   flutter config --enable-windows-desktop
   flutter doctor
   ```

---

## Getting Started

### 1. Install dependencies

```bash
cd desktopapp
flutter pub get
```

### 2. Run in debug mode (Windows only)

```bash
flutter run -d windows
```

### 3. First-time setup

1. The app opens with a WebView loading the default URL
2. Press **Ctrl+,** or click the gear icon to open Settings
3. Set your POS URL (e.g., `https://yourcompany.digitex.uz/`)
4. Configure printer IP address and port (default: `192.168.0.150:9100`)
5. Select paper width (57mm or 80mm)
6. Click "Test Connection" to verify printer is reachable
7. Click "Print Test Page" to verify receipt layout
8. Save settings

---

## Building for Production

### Build release executable

```bash
cd desktopapp
flutter build windows --release
```

Output: `build/windows/x64/runner/Release/`

### Directory contents to distribute

```
Release/
├── digitex_pos.exe          # Main executable
├── flutter_windows.dll
├── webview_windows_plugin.dll
├── data/
│   └── ...                  # Flutter assets
└── ...                      # Other DLLs
```

**Important:** Distribute the entire `Release/` folder, not just the `.exe`.

### Creating an Installer (Inno Setup)

1. Download Inno Setup: https://jrsoftware.org/isdl.php
2. Create a script `installer.iss`:

```iss
[Setup]
AppName=Digitex POS
AppVersion=1.0.0
AppPublisher=Digitex
DefaultDirName={autopf}\Digitex POS
DefaultGroupName=Digitex POS
OutputBaseFilename=DigitexPOS-Setup
Compression=lzma2
SolidCompression=yes
SetupIconFile=windows\runner\resources\app_icon.ico

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs

[Icons]
Name: "{group}\Digitex POS"; Filename: "{app}\digitex_pos.exe"
Name: "{autodesktop}\Digitex POS"; Filename: "{app}\digitex_pos.exe"

[Run]
Filename: "{app}\digitex_pos.exe"; Description: "Launch Digitex POS"; Flags: nowait postinstall skipifsilent
```

3. Compile: `iscc installer.iss`

---

## Auto-Start on Windows Boot

Toggle in Settings screen ("Windows ishga tushganda avtomatik ochilsin").

This adds/removes a registry key:
```
HKCU\Software\Microsoft\Windows\CurrentVersion\Run\DigitexPOS
```

Manual setup (if needed):
```cmd
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v DigitexPOS /t REG_SZ /d "C:\Program Files\Digitex POS\digitex_pos.exe" /f
```

To remove:
```cmd
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v DigitexPOS /f
```

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+,` | Open Settings |
| `F5` | Reload WebView |
| `F12` | Open DevTools (debug only) |

---

## Printer Configuration

### Supported Printers

Any thermal receipt printer accessible via LAN (TCP/IP) on port 9100:
- Xprinter (XP-58, XP-80 series)
- HOIN (HOP-E801, etc.)
- Epson TM series (network models)
- Star Micronics (network models)

### Codepage Selection

| Codepage | Use Case |
|----------|----------|
| CP866 | Russian Cyrillic + Uzbek Latin (recommended) |
| CP437 | ASCII/Latin only |
| CP1251 | Windows Cyrillic (some printers) |

If Cyrillic characters print as garbage, try switching between CP866 and CP1251.

### Troubleshooting Printer

1. **"Printerga ulanib bo'lmadi"** — Cannot connect
   - Verify printer is powered on and on the same network
   - Ping the printer: `ping 192.168.0.150`
   - Check port 9100 is not blocked by firewall

2. **Garbled characters**
   - Switch codepage in Settings (CP866 / CP1251)

3. **Paper not cutting**
   - Not all printers support auto-cut
   - Check printer hardware settings

---

## Vue Frontend Integration

The desktop bridge is in `inventory-frontend/src/utils/desktop-bridge.js`.

Detection:
```javascript
import { isDesktopApp } from '@/utils/desktop-bridge'

if (isDesktopApp()) {
  // Running in Flutter desktop wrapper
}
```

When in desktop mode:
- `ReceiptPreview.vue` sends receipt data via `sendPrintCommand()` instead of `iframe.print()`
- `SaleDetail.vue` fetches receipt from API and sends to Flutter for thermal printing

When in a regular browser — all existing flows work unchanged.

### Adding New Message Types

In Flutter (`home_screen.dart`):
```dart
if (type == 'OPEN_CASH_DRAWER') {
  await _handleCashDrawer();
}
```

From Vue:
```javascript
window.chrome.webview.postMessage(
  JSON.stringify({ type: 'OPEN_CASH_DRAWER' })
)
```
