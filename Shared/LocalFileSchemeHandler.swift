import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves local images and media to the preview over `mded-file://`.
///
/// The preview page's base URL is the document's folder under this scheme, so
/// `![](images/a.png)` resolves to `mded-file:///…/images/a.png` and is read here,
/// in-process. Loading from `file://` instead depends on WebKit's sandbox granting
/// the web content process read access, which it doesn't for ordinary folders.
///
/// Only images, audio and video are served. Page JavaScript is disabled, so a
/// document can display these files but never read their bytes.
final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated static let scheme = "mded-file"

    /// Base URL for a page whose relative references resolve in `directory`.
    nonisolated static func baseURL(forDirectory directory: URL) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = ""
        let path = directory.standardizedFileURL.path
        components.path = path.hasSuffix("/") ? path : path + "/"
        return components.url
    }

    /// The file a `mded-file:` URL refers to.
    nonisolated static func fileURL(for url: URL) -> URL? {
        guard url.scheme?.lowercased() == scheme, !url.path.isEmpty else { return nil }
        return URL(fileURLWithPath: url.path)
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let requestURL = task.request.url,
              let fileURL = Self.fileURL(for: requestURL),
              let type = UTType(filenameExtension: fileURL.pathExtension),
              type.conforms(to: .image) || type.conforms(to: .audiovisualContent),
              let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        // An HTTP response, because fetch() (used when exporting) takes the blob's
        // type from the Content-Type header rather than the response's MIME type.
        let headers = [
            "Content-Type": type.preferredMIMEType ?? "application/octet-stream",
            "Content-Length": String(data.count),
        ]
        guard let response = HTTPURLResponse(url: requestURL, statusCode: 200, httpVersion: "HTTP/1.1",
                                             headerFields: headers) else {
            task.didFailWithError(URLError(.cannotParseResponse))
            return
        }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        // Nothing to cancel: `start` answers synchronously.
    }
}
