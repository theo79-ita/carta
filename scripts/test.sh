#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/test-cache
swiftc -parse-as-library -module-cache-path "$PWD/.build/test-cache" \
  Sources/Carta/Document.swift Sources/Carta/A4Paper.swift Sources/Carta/MarkdownInsertion.swift Sources/Carta/MarkdownMenu.swift Sources/Carta/TypewriterTextView.swift Tests/CartaTests/TestRunner.swift -o .build/CartaTests
.build/CartaTests "$PWD/Sources/Carta/Resources" "$@"
