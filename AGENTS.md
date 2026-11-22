# Battery % Viewer

Battery % Viewer is a native macOS and Windows accessibility utility. It shows the battery percentage in resizable text, reports charging and power status, and speaks both using installed system voices. Users can enable power-change and low-battery announcements or keep monitoring active after they close the window. The Mac menu bar and Windows notification area provide speech, reopen, and quit commands when background mode is enabled.

## Project layout

- `macOS/` contains the SwiftUI app, AppKit menu bar integration, and IOKit battery readings.
- `Windows/` contains the WPF app, Windows notification area integration, and Windows Installer source.
- `MAC AppFiles/` and `windows App Files/` contain legacy Python versions and assets. The native builds reuse the existing application icons from these folders.
- `tests/` contains the battery-state checks and the Windows UI Automation smoke test.

## Every app update

1. Bump the app version on both platforms in the same source change. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `macOS/Info.plist`. Match the display version in the four-part Windows `AssemblyVersion` in `Windows/Viewer.cs` and `assemblyIdentity` in `Windows/app.manifest`. Update the version shown in `README.md`. Use the same version in release titles and downloads.
2. Build, install, and launch the updated app on macOS and on Windows, including when the code change affects only one platform. Verify **Settings → About** shows the new version on both. Test the changed behavior through the installed apps with keyboard and accessibility checks where relevant.
3. Check the main battery display and power status, speech and Settings, and close and reopen behavior whenever the change touches them. Preserve existing preferences and the single-instance behavior. Report any platform or interaction that could not be tested.

## Build and verification

- On Mac, run `./script/build_and_run.sh --verify` for a build and launch check. Run the battery-state tests with `mkdir -p build && xcrun swiftc macOS/Battery.swift tests/BatteryReadings.swift -o build/battery-tests && build/battery-tests`.
- On Windows, run `.\Windows\Build.ps1 -Install`, open **Battery % Viewer** from Start, and run `.\tests\WindowsSmoke.ps1` in the interactive Windows session.
- For a release, run `./script/package_macos.sh` for the universal DMG and `.\Windows\Package.ps1 -WixBin <WiX-3.14.1-binaries-folder>` for the per-user MSI and portable executable. Verify the version and launch from the packaged builds. Check the signing status before describing them as ready for public distribution.
- GitHub drafts can include both platform builds under one version tag. Target the source commit used to build the artifacts and leave the release in draft until publication is requested.
