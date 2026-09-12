# DDNet iOS Client

This document describes the iOS port of the DDNet client, targeting iOS 27 and backwards-compatible with iOS 15.0+.

---

## 1. Specifications & Compatibility

* **Supported iOS Versions:** iOS 15.0 – iOS 27.0+ (iPhone and iPad)
* **Minimum Deployment Target:** iOS 15.0 (`MinimumOSVersion = 15.0`)
  * Fully compliant with App Store Connect requirements.
* **Target Architecture:** `arm64` (Apple Silicon iPhone / iPad)
* **Simulator Architectures:** `arm64` (`aarch64-apple-ios-sim`), `x86_64` (`x86_64-apple-ios`)
* **Graphics Backend:** OpenGL ES 3.0 (`GfxBackend = GLES`) via UIKit and SDL2
* **Audio Backend:** SDL2 Audio with CoreAudio / AudioToolbox
* **Input System:**
  * Multi-touch touch controls (`cl_touch_controls = 1` by default)
  * Virtual floating back button for iOS (`cl_back_button = 1` by default)
  * Hardware mouse / trackpad support via `UIApplicationSupportsIndirectInputEvents`
  * Game controller support via GameController framework & CoreBluetooth
* **Filesystem & Storage:**
  * Application sandbox `Documents/` directory (`UIFileSharingEnabled = true`, `LSSupportsOpeningDocumentsInPlace = true`)
  * Accessible via the iOS Files app and iTunes / Finder file sharing
  * In-game folder navigation links using `shareddocuments://` scheme

---

## 2. CI/CD & Build Environment

The client is built reproducibly on GitHub Actions:

* **Workflow:** [`.github/workflows/build-ios.yml`](.github/workflows/build-ios.yml)
* **Runner:** `xcode-27` (macOS 26 with Xcode 27.0 image)
  * Fallback / configurable runner: `macos-26` (Xcode 26.6)
* **Xcode Version:** Xcode 27.0 (Build `27A5252f`)
* **iOS SDK Version:** `iPhoneOS27.0.sdk` (Device), `iPhoneSimulator27.0.sdk` (Simulator)
* **Rust Toolchain:** Stable Rust with targets:
  * `aarch64-apple-ios`
  * `aarch64-apple-ios-sim`
* **Precompiled Libraries:** `ddnet-libs` submodule providing multi-architecture xcframeworks:
  * `libSDL2.xcframework`
  * `libcurl.xcframework`
  * `libfreetype.xcframework`
  * `libpng16.xcframework`
  * `libsqlite3.xcframework`
  * `libogg.xcframework`
  * `libopus.xcframework`
  * `libopusfile.xcframework`
  * `libwavpack.xcframework`

---

## 3. Build Instructions

### Prerequisites (Local macOS Build)

1. macOS with Xcode 26.x or 27.x installed (`xcode-select -p` pointing to developer directory).
2. CMake 3.20 or newer.
3. Rust (stable) with iOS targets:
   ```bash
   rustup target add aarch64-apple-ios aarch64-apple-ios-sim
   ```
4. Submodules initialized:
   ```bash
   git submodule update --init --recursive
   ```

### Building for Physical iOS Device (arm64 Release)

```bash
scripts/ios/cmake_ios.sh device DDNet org.ddnet.client Release build-ios-device
```

### Packaging into IPA

```bash
mkdir -p Payload artifacts
cp -R build-ios-device/Release-iphoneos/DDNet.app Payload/
# Ad-hoc sign the bundle structure
codesign --force --deep --sign - "Payload/DDNet.app"
# Create IPA archive
zip -qry artifacts/DDNet.ipa Payload
```

### Building for iOS Simulator (Debug)

```bash
scripts/ios/cmake_ios.sh sim-arm64 DDNet org.ddnet.client Debug build-ios-sim
```

### Running Static Validation

```bash
chmod +x scripts/ios/validate_ipa.sh
scripts/ios/validate_ipa.sh artifacts/DDNet.ipa DDNet org.ddnet.client
```

---

## 4. Code Signing & Installation

### Ad-Hoc Signed Builds (Default CI Artifacts)
Device builds created without a development team are ad-hoc signed (`codesign --sign -`). This creates a valid Mach-O Code Directory, CDHash, and sealed resource manifest without requiring private Apple Developer keys.

* **TrollStore:** Can install and run `DDNet.ipa` directly without revokes or signing expiration.
* **AltStore / SideStore:** Re-signs `DDNet.ipa` using your personal Apple ID (free or developer account).
* **Sideloadly / Scarlet:** Sideloads and signs `DDNet.ipa` with personal or enterprise certificate.

### Automatic Apple Developer Signing
To build with automatic code signing using an official Apple Developer Team:

```bash
IOS_DEVELOPMENT_TEAM="XXXXXXXXXX" scripts/ios/cmake_ios.sh device DDNet org.ddnet.client Release build-ios-device
```

---

## 5. Verification & Validation Summary

### Automated CI Verification (Verified)
- [x] **Compilation:** Clean compilation on Xcode 27.0 with iOS 27 SDK and arm64 Clang/LLVM.
- [x] **Rust Bridge:** Successfully built native Rust bridge for `aarch64-apple-ios` and `aarch64-apple-ios-sim`.
- [x] **Simulator Execution:** Simulator booted (`simctl`), DDNet installed, launched, initialized graphics and sound, and cleanly exited saving `settings_ddnet.cfg`.
- [x] **Archive Structure:** IPA ZIP archive verified, `Payload/DDNet.app` structure validated.
- [x] **Mach-O Architecture:** Verified `arm64` thin binary using `file`, `lipo`, and `otool`.
- [x] **Asset Bundles:** App icon catalog `Assets.car` generated and placed in root bundle.
- [x] **Bundled Data:** DDNet `data/maps` (all default maps), `data/audio`, and `storage.cfg` bundled and verified.
- [x] **Static IPA Validation:** `scripts/ios/validate_ipa.sh` executed in CI and passed 100% of checks.

### Physical Device Considerations (Requires Physical Testing)
- **Multi-Touch Ergonomics:** Responsiveness and feel of the virtual dual touch joysticks and floating back button on different physical screen sizes.
- **Display Cutout / Dynamic Island:** Physical display cutouts on iPhone 14 Pro / 15 / 16 / 17 series devices.
- **Hardware Refresh Rates:** 60 Hz / 120 Hz ProMotion display smoothness.
- **Cellular Networking:** Network connectivity when transitioning between cellular and Wi-Fi networks in active multiplayer games.
