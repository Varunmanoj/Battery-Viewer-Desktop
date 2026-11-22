# Battery % Viewer

Battery % Viewer makes a computer’s battery percentage and power status easier to see and hear. Version 10 has native Mac and Windows interfaces with a large, resizable reading, keyboard controls, and on-device speech.

## Use the viewer

Open **Battery % Viewer** from Applications on Mac or from Start on Windows. The display checks the battery every five seconds while the app is running. **Speak battery** reads the current percentage and power status aloud. A plugged-in laptop can show **Connected to power** while charging is paused. A desktop without a battery shows **No battery detected**.

Choose **View → Battery Percentage Size** or open **Settings** to adjust the battery text with a slider from 48 to 180 points. With the slider focused, use the arrow keys for one-point adjustments. In Settings you can also switch between system, light and dark appearance or select and preview an installed voice. The About section shows the installed version. Opening the app again brings its existing window forward. Settings are saved for your user account. Windows contrast themes take precedence over the app’s palette.

Automatic speech is off at first. In **Settings → Automatic announcements**, turn on **Announce low battery** and set **Low battery threshold** from 1% to 100%. The default is 20%. The alert plays when the battery drops to or below the threshold while unplugged, or when you unplug at or below the threshold. You can also enable an announcement whenever power is connected or disconnected. The app must be running for these announcements.

### Keyboard shortcuts

| Action | Mac | Windows |
| --- | --- | --- |
| Speak battery | Command+S | Ctrl+S |
| Speak power status | Command+C | Ctrl+C |
| Open Settings | Command+, | Ctrl+, |
| Light appearance | Command+L | Ctrl+L |
| Dark appearance | Command+D | Ctrl+D |
| Close Settings | Escape or Done | Escape or Done |
| Quit | Command+Q | Alt+F4 |

Use Tab and Shift+Tab to move between controls. On Mac, enable Keyboard navigation in System Settings to tab through every control. VoiceOver and Windows screen readers can navigate the battery reading and controls through their normal reading commands.

## Build and install

**Mac** — On a Mac with Xcode installed, run `./script/build_and_run.sh` to build and launch. Use `./script/build_and_run.sh --build` to build only. Copy `dist/Battery % Viewer.app` to Applications to install. The universal bundle targets macOS 13 and later and is ad-hoc signed for local use.

**Windows** — On 64-bit Windows with .NET Framework 4.8 and the Windows 10 or 11 SDK installed, run `.\Windows\Build.ps1 -Install` in PowerShell from the project root. Open **Battery % Viewer** from Start. The build also produces a portable `dist\BatteryViewer.exe`. The SDK is only needed for compilation. The application runs on Windows 10 (version 1703 or later with .NET Framework 4.8 installed) and Windows 11 using local Windows speech voices.

Current sources are in `macOS` and `Windows`. The older Python sources and installers in `MAC AppFiles` and `windows App Files` belong to previous releases.

[Original Battery % Viewer website](https://sites.google.com/view/batteryviewer-low-vision/home)
