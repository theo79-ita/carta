import AppKit
import SwiftUI
import WebKit
import UniformTypeIdentifiers

@MainActor final class WebActions: ObservableObject {
    weak var view: WKWebView?
    @Published var readingTime: (documentID: String, seconds: Int)?
    func find(_ query: String, backwards: Bool = false, state: ReaderState) {
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.wraps = true
        configuration.caseSensitive = false
        view?.find(query, configuration: configuration) { result in
            guard state.searchText == query else { return }
            state.searchResult = query.isEmpty ? "" : (result.matchFound ? "Trovato" : "Nessun risultato")
        }
    }
    func scroll(to id: String) {
        view?.callAsyncJavaScript("window.Carta.scrollTo(id)", arguments: ["id": id], in: nil, in: .page, completionHandler: nil)
    }
    func printDocument() {
        guard let view else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = 36; info.bottomMargin = 36; info.leftMargin = 36; info.rightMargin = 36
        let operation = view.printOperation(with: info)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }
}

struct WebReader: NSViewRepresentable {
    @ObservedObject var state: ReaderState
    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "carta")
        config.setURLSchemeHandler(context.coordinator.assets, forURLScheme: "carta-asset")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.allowsMagnification = true
        state.web.view = view
        context.coordinator.view = view
        let page = Resource.text("reader.html")
            .replacingOccurrences(of: "/* MARKED_LIBRARY */", with: Resource.text("vendor/marked.js"))
            .replacingOccurrences(of: "/* PURIFY_LIBRARY */", with: Resource.text("vendor/purify.js"))
            .replacingOccurrences(of: "/* READER_SCRIPT */", with: Resource.text("reader.js"))
            .replacingOccurrences(of: "/* READER_STYLES */", with: Resource.text("reader.css"))
        view.loadHTMLString(page, baseURL: nil)
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) { context.coordinator.render() }
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "carta")
        nsView.navigationDelegate = nil
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let state: ReaderState
        let assets = LocalAssetHandler()
        weak var view: WKWebView?
        var ready = false
        var previous: String?
        init(state: ReaderState) { self.state = state }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true; previous = nil; render()
        }

        func render() {
            guard ready, let view else { return }
            assets.root = state.document.url?.deletingLastPathComponent()
            var base = URLComponents()
            base.scheme = "carta-asset"; base.host = "local"
            base.path = (assets.root?.path ?? "/") + "/"
            let payload: [String: Any] = [
                "text": state.editingText, "theme": state.theme.rawValue, "fontSize": state.fontSize,
                "source": state.sourceVisible, "documentID": state.documentID,
                "readingSeconds": state.readingDocument.readingSeconds,
                "documentURL": state.document.url?.absoluteString ?? "", "assetBase": base.url!.absoluteString
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
                  let json = String(data: data, encoding: .utf8), previous != json else { return }
            previous = json
            view.evaluateJavaScript("window.Carta.render(\(json))") { [weak self] _, error in
                if let error { self?.state.errorMessage = "Impossibile visualizzare il documento: \(error.localizedDescription)" }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else { return }
            if let text = body["copy"] as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            guard message.webView === state.web.view, body["documentID"] as? String == state.documentID,
                  body["source"] as? Bool == state.sourceVisible else { return }
            if let seconds = body["remainingSeconds"] as? Int {
                state.web.readingTime = (state.documentID, seconds)
            }
            if let items = body["headings"] as? [[String: Any]] {
                let outline = items.compactMap { item -> OutlineItem? in
                    guard let id = item["id"] as? String, let title = item["title"] as? String,
                          let level = item["level"] as? Int else { return nil }
                    return OutlineItem(id: id, title: title, level: level)
                }
                state.outline.replaceItems(outline)
                if !state.searchText.isEmpty { state.web.find(state.searchText, state: state) }
            }
            if let activeID = body["activeHeadingID"] {
                state.outline.select(activeID as? String)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if url.absoluteString == "about:blank", action.navigationType == .other { decisionHandler(.allow); return }
            if action.navigationType == .linkActivated {
                if ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
                else if url.isFileURL, MarkdownDocument.extensions.contains(url.pathExtension.lowercased()) { state.open(url) }
            }
            decisionHandler(.cancel)
        }
    }
}

final class LocalAssetHandler: NSObject, WKURLSchemeHandler {
    var root: URL?
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let request = urlSchemeTask.request.url, let root,
              let file = AssetAccess.resolve(request, inside: root),
              let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= MarkdownDocument.maximumBytes,
              let data = try? Data(contentsOf: file) else {
            urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile)); return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let response = URLResponse(url: request, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil)
        urlSchemeTask.didReceive(response); urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
