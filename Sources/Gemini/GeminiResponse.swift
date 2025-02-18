import Foundation

struct GeminiHeader {
    let status: Int
    let meta: String

    init?(raw: String) {
        let parts = raw.split(maxSplits: 2, whereSeparator: \.isWhitespace)

        guard let first = parts.first, let status = Int(String(first)) else {
            return nil
        }

        self.status = status
        self.meta = parts.last.flatMap(String.init) ?? ""
    }
}

struct GeminiResponse {
    let header: GeminiHeader
    let body: Data?

    init?(_ data: Data) {
        let parts = data.split(separator: 13, maxSplits: 2) // TODO: check for [13, 10] (CRLF)
        guard let first = parts.first,
              let string = String(data: first, encoding: .utf8),
              let header = GeminiHeader(raw: string) else {
            return nil
        }
        self.header = header
        self.body = parts.last?.advanced(by: 1)
    }

    var isInput: Bool {
        header.status >= 10 && header.status < 20
    }

    var isOk: Bool {
        header.status >= 20 && header.status < 30
    }

    var isRedirect: Bool {
        header.status >= 30 && header.status < 40
    }

    var isError: Bool {
        header.status >= 40
    }
}
