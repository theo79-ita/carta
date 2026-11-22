# Carta

Carta is a native Markdown editor and reader for macOS with a live preview, a clickable outline, and an A4 typewriter mode with mechanical key sounds and a margin bell.

Reading, Writing and Typewriter modes share the same text, including unsaved edits. In Typewriter mode, the carriage indicator follows the caret on a physically calibrated A4 page.

**Version 0.2.13 Glass** · macOS 13 or later · English and Italian · MIT-licensed project

[Italian documentation](docs/README.it.md)

## Build and open Carta

On a Mac with Apple's Command Line Tools for Xcode and Swift 5.9 or later, open Terminal in the directory containing `Package.swift` and run:

```sh
./scripts/build-app.sh
open dist/Carta.app
```

If the developer tools are missing, install them with `xcode-select --install`. The default build targets the architecture of the Mac doing the build. The build uses the macOS SDK and two JavaScript libraries already included in this repository. You can build offline once the tools are installed.

## Use Carta

Press **⌘O** to open a document, drag one into the window, or choose **Open With → Carta** in Finder. Press **⌘N** for a new document. Use the mode selector at the top left or the shortcuts below.

Carta follows your preferred macOS language. To choose English or Italian just for Carta, use **System Settings → General → Language & Region → Applications**, then reopen Carta.

| Mode | Shortcut | What you can do |
| --- | --- | --- |
| Reading | ⌥⌘1 | Follow headings in the outline, search the document, copy a code block or print to PDF. The remaining reading time follows your scroll position, starting from an estimate of 220 words per minute. |
| Writing | ⌥⌘2 | Edit plain Markdown with soft wrapping. Tap and release Option for a keyboard-driven formatting menu at the caret, or right-click a selection to format it. |
| Typewriter | ⌥⌘3 | Write on a calibrated A4 sheet with a 60-column margin. The bell rings six characters before the margin. Press Return for a new line, click the lock to release the margin, or click the speaker to mute the sound. |

In either writing mode, use **⌘S** to save or **⇧⌘S** for Save As. In reading mode, use **⌘F** to search, **⇧⌘U** to view the Markdown source and **⌘P** to print or save a PDF. [Full user guide](docs/USER_GUIDE.md)

## Documents and privacy

Carta opens one document at a time, up to 20 MiB. It reads UTF-8, UTF-16 with a byte-order mark and Windows-1252. New files use UTF-8. Supported extensions are `.md`, `.markdown`, `.mdown`, `.mkd`, `.mkdn`, `.mdx` and `.txt`. Carta reads MDX as Markdown text.

The reader processes text locally. Marked generates HTML and DOMPurify filters it before WebKit displays it. Opening a document that embeds a remote image can contact the host serving that image. Carta stores recent file paths and preferences in macOS user defaults.

## Tests

```sh
./scripts/test.sh
```

Run the full suite in a logged-in macOS desktop session. For a run limited to document and editor checks, use `./scripts/test.sh --without-webkit`. Both modes use AppKit. [Build and test guide](docs/DEVELOPMENT.md)

## License and credits

Carta's original code, documentation, icon artwork and typewriter sounds are available under the MIT License. The bundled renderer includes Marked 18.0.14 (MIT) and DOMPurify 3.4.16 (Apache-2.0 or MPL-2.0 upstream, distributed here under Apache-2.0). Third-party components retain their own terms. [Project license](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md)

For the source inventory, Apple frameworks and dependency update procedure, see the [development guide](docs/DEVELOPMENT.md). For tagging and distributing a release, see the [GitHub release guide](docs/PUBLISHING.md).
