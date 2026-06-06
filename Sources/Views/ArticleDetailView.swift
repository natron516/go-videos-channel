import SwiftUI
import os

#if !os(tvOS)
import WebKit

private let logger = Logger(subsystem: "com.gospeloutreacholympia.tv", category: "ArticleDetail")

struct ArticleDetailView: View {
    let article: GOArticle

    private var hasPDF: Bool {
        guard let url = article.pdfUrl, !url.isEmpty else { return false }
        return URL(string: url) != nil
    }

    private var hasRealContent: Bool {
        let stripped = article.content
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !stripped.isEmpty
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Color.clear.appBackground()

            if hasPDF, let pdfUrl = URL(string: article.pdfUrl!) {
                PDFWebView(url: pdfUrl)
            } else if hasRealContent {
                ArticleWebView(htmlContent: article.content, title: article.title)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("No content available")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("pdfUrl: \(article.pdfUrl ?? "none")")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
        }
        .navigationTitle(article.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PDF viewer via WKWebView
struct PDFWebView: UIViewRepresentable {
    let url: URL
    @State private var hasLoaded = false

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = UIColor.black
        webView.scrollView.backgroundColor = UIColor.black
        webView.isOpaque = false
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[PDF] Load failed: \(error.localizedDescription)")
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[PDF] Provisional load failed: \(error.localizedDescription)")
            // Fallback: try opening via Google Docs viewer
            if let url = webView.url ?? navigation?.effectiveContentMode as? URL {
                let googleViewer = URL(string: "https://docs.google.com/gview?embedded=true&url=\(url.absoluteString)")!
                webView.load(URLRequest(url: googleViewer))
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("[PDF] Loaded successfully")
        }
    }
}

// MARK: - WKWebView wrapper for HTML rendering
struct ArticleWebView: UIViewRepresentable {
    let htmlContent: String
    let title: String

    private var styledHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
        <style>
            :root { color-scheme: dark; }
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', Arial, sans-serif;
                background-color: #000000;
                color: #EBEBF5;
                font-size: 17px;
                line-height: 1.65;
                padding: 20px 20px 60px 20px;
                max-width: 100%;
                overflow-x: hidden;
                -webkit-text-size-adjust: 100%;
            }
            h1, h2, h3, h4, h5, h6 {
                color: #FFFFFF;
                font-weight: 700;
                margin: 1.4em 0 0.6em;
                line-height: 1.3;
            }
            h1 { font-size: 1.55em; }
            h2 { font-size: 1.3em; }
            h3 { font-size: 1.15em; }
            p { margin: 0.9em 0; color: #C7C7CC; }
            a { color: #3478F6; text-decoration: none; }
            img { max-width: 100%; height: auto; border-radius: 8px; margin: 1em 0; }
            blockquote {
                border-left: 3px solid #48484A;
                padding-left: 16px;
                margin: 1em 0;
                color: #8E8E93;
                font-style: italic;
            }
            ul, ol { margin: 0.8em 0; padding-left: 1.5em; }
            li { margin: 0.3em 0; color: #C7C7CC; }
            code {
                background-color: #1C1C1E;
                color: #FF375F;
                padding: 2px 6px;
                border-radius: 4px;
                font-size: 0.9em;
                font-family: 'SF Mono', Menlo, monospace;
            }
            pre {
                background-color: #1C1C1E;
                padding: 14px;
                border-radius: 8px;
                overflow-x: auto;
                margin: 1em 0;
            }
            pre code { background: none; padding: 0; color: #EBEBF5; }
            hr { border: none; border-top: 1px solid #38383A; margin: 2em 0; }
        </style>
        </head>
        <body>
        \(htmlContent)
        </body>
        </html>
        """
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = UIColor.black
        webView.scrollView.backgroundColor = UIColor.black
        webView.isOpaque = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(styledHTML, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

#endif
