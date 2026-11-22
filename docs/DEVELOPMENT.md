# Building and maintaining Carta

## Toolchain

Use macOS, Apple's Command Line Tools for Xcode (or full Xcode) and a matching Swift compiler and macOS SDK. The package declares Swift tools 5.9 and a macOS 13 deployment target. For native Liquid Glass controls, build with Swift 6.2 or later and the macOS 26 SDK or newer, then run on macOS 26 or later. Older combinations use SwiftUI material. The precompiled icon assets are checked in, so Icon Composer is only needed to edit the icon.

```sh
swift --version
xcrun --sdk macosx --show-sdk-version
./scripts/build-app.sh
open dist/Carta.app
```

The script builds the SwiftPM executable in release mode, checks the linked SDK, assembles the app bundle and signs it ad hoc for local use. For version 0.2.12 it writes `dist/Carta.app` and `dist/Carta-0.2.12-Glass.zip`. That ZIP contains the named app bundle and its editable icon. SwiftPM build products go under `.build/`. Both output directories are ignored by Git.

If a restricted build environment reports `Operation not permitted` during `GenerateDSYMFile`, recent Swift toolchains can produce the same application without a separate debug-symbol bundle:

```sh
./scripts/build-app.sh -debug-info-format none
```

Use the default command when you want debug symbols for crash reports.

## Source map

| Location | Contents |
| --- | --- |
| `Package.swift` | Executable target, minimum OS and resource-copy rule. |
| `Sources/Carta/CartaApp.swift`, `ReaderState.swift`, `Document.swift` | Application lifecycle and menu commands, document state, file I/O and encoding. |
| `Sources/Carta/WriterView.swift`, `TypewriterTextView.swift`, `A4Paper.swift`, `WritingGlass.swift` | Writing modes, typewriter interaction and sounds, physical page sizing and controls. |
| `Sources/Carta/MarkdownMenu.swift`, `MarkdownInsertion.swift` | Formatting commands, keyboard menu and text transformations. |
| `Sources/Carta/ReaderView.swift`, `WebReader.swift`, `Resources/reader.*` under the same directory | Reader window, WebKit bridge, page template, styles and rendering logic. |
| `Sources/Carta/Resources/` | Welcome document, eight WAV samples, reader resources and vendored JavaScript. |
| `Artwork/` | Editable Icon Composer document, compiled catalog and fallback ICNS. |
| `Tests/CartaTests/TestRunner.swift`, `scripts/` | Native test runner, test/build commands and app metadata. |

## Platform dependencies

The Swift package has no external Swift package dependencies. Node.js, npm, CocoaPods and a CDN are unnecessary for the normal build.

| Apple module | Use in the project |
| --- | --- |
| SwiftUI | Windows, controls, reading and writing views, adaptive materials. |
| AppKit | Native text editing, menus, file dialogs, printing, clipboard and WAV playback through NSSound. |
| Foundation | Document bytes, encodings, file URLs, preferences and serialization. |
| WebKit | WKWebView reader, script messages, find-in-page and local image scheme handler. |
| UniformTypeIdentifiers | File types in open/save panels and MIME types for local images. |
| CoreGraphics, IOKit.graphics, Darwin | Display size and modes, native display flags and hardware model lookup for A4 calibration. |
| Carbon.HIToolbox | Left and right Option key codes for the Markdown menu. |

## Update a browser library

1. Choose a specific upstream release and read its release notes. Retrieve the published browser build and license files for that version.
2. For Marked, copy `lib/marked.umd.js` from the published package to `Sources/Carta/Resources/vendor/marked.js`. For DOMPurify, copy `dist/purify.min.js` to `purify.js` in the same directory. Keep the upstream banners.
3. Update the accompanying license texts and check the new bundle for embedded notices. DOMPurify 3.4.16 includes a Babel regenerator notice. Marked's license file includes a separate notice for Markdown.
4. Record the version and SHA-256 in the root notices, update the README, and run the full suite. The resource-copy rule and packaging script carry the relevant files into the app.

```sh
shasum -a 256 Sources/Carta/Resources/vendor/marked.js Sources/Carta/Resources/vendor/purify.js
./scripts/test.sh
./scripts/build-app.sh
```

[Third-party notices](../THIRD_PARTY_NOTICES.md) · [Marked upstream](https://github.com/markedjs/marked) · [DOMPurify upstream](https://github.com/cure53/DOMPurify)

## Tests

The repository uses a custom Swift test runner. Execute `./scripts/test.sh` from a logged-in macOS desktop session. It compiles the runner with `swiftc` and exercises document decoding and saves, external changes, physical page layout, typewriter interaction, formatting operations and the Option menu. WebKit checks cover the rendered document, tables, outline navigation and the reading-time estimate.

```sh
./scripts/test.sh --without-webkit
```

This shorter run still uses AppKit. Use it to isolate document and editor results when the WebKit process is unavailable. If the full runner reports a WebKit timeout in a restricted session, run it on a Mac with an active desktop before validating a binary release.

## Prepare the next version

Update `CFBundleShortVersionString`, `CFBundleVersion`, `CFBundleName` and `CFBundleDisplayName` in `scripts/Info.plist`. Increment the patch number for fixes and small improvements. For a significant feature, increment the minor number and reset the patch number. Update version-specific examples and output filenames in the documentation before tagging the release.
