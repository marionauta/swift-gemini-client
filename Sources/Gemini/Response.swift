import Foundation

struct Header {
    let status: Int
    let meta: String

    init?(raw: String) {
        let parts = raw.split(whereSeparator: \.isWhitespace)

        guard let status = Int(String(parts[0])) else {
            return nil
        }

        self.status = status
        self.meta = String(parts[1...].joined(separator: " "))
    }
}

struct Response {
    let header: Header
    let body: String?

    init?(_ string: String) {
        let components = string.components(separatedBy: "\n")

        guard let first = components.first, let header = Header(raw: first) else {
            return nil
        }

        self.header = header
        self.body = String(components[1...].joined(separator: "\n"))
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
