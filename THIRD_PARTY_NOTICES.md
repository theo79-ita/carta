# Third-party notices

Carta embeds two browser libraries. Their version banners and the copyright notices in the distributed files have been preserved. The complete license texts accompany both the source tree and the built application.

| Component | Role in Carta | License and attribution |
| --- | --- | --- |
| [Marked 18.0.14](https://github.com/markedjs/marked/tree/v18.0.14) | Converts Markdown to HTML with GitHub Flavored Markdown enabled. | MIT. MarkedJS and Christopher Jeffrey. The upstream file also includes John Gruber's 2004 Markdown copyright, redistribution conditions and disclaimer. [Complete Marked and Markdown notices](Sources/Carta/Resources/vendor/marked-LICENSE.txt) |
| [DOMPurify 3.4.16](https://github.com/cure53/DOMPurify/tree/3.4.16) | Sanitizes the generated HTML before Carta inserts it into the reader. | Copyright Cure53 and other contributors. Upstream offers Apache-2.0 **or** MPL-2.0. Carta distributes this copy under Apache-2.0. [Apache license](Sources/Carta/Resources/vendor/purify-LICENSE.txt) · [Upstream MPL alternative](Sources/Carta/Resources/vendor/purify-LICENSE-MPL.txt) |
| [Babel helpers and regenerator runtime](https://github.com/babel/babel/blob/main/packages/babel-helpers/LICENSE) | Helper code embedded in the DOMPurify browser file. The embedded banner identifies the regenerator runtime. | MIT. Sebastian McKenzie and other contributors, and Facebook, Inc. for the regenerator helpers. The bundle gives no separate helper version. [Full helper notice](Sources/Carta/Resources/vendor/babel-helpers-LICENSE.txt) |

## Files included in this release

| File | SHA-256 of the distributed JavaScript |
| --- | --- |
| `Sources/Carta/Resources/vendor/marked.js` | `21568877a938d2c4e7d74e27f18e60da96bb73a68809610ca39216e1efebae62` |
| `Sources/Carta/Resources/vendor/purify.js` | `2c90a9b46d6463f26038a29b686e82bc91de01fdac9d5229e7cfe3b360134ea2` |

These hashes identify the exact copies in this release. Marked's browser bundle is published as `lib/marked.umd.js` in the npm package. DOMPurify's is `dist/purify.min.js`. [Marked package](https://www.npmjs.com/package/marked/v/18.0.14) · [DOMPurify package](https://www.npmjs.com/package/dompurify/v/3.4.16)

## Project assets and system components

The icon illustration and the eight WAV files in `Sources/Carta/Resources/TypewriterSounds/` were created for Carta. The project MIT license covers these resources. The editable Apple Icon Composer document is `Artwork/Carta.icon`. The build uses `Artwork/Assets.car` and `Artwork/Carta.icns` for the app icon.

Carta links against Apple libraries provided with macOS. The source archive contains the app's own icon catalog and resources. The operating system supplies SwiftUI, AppKit, WebKit and the other platform frameworks at runtime.

To find the notices in a built app, choose **Show Package Contents** in Finder and open `Contents/Resources/Licenses/`. The resource bundle also carries the individual upstream texts alongside the JavaScript files.
