import Foundation

let handler = GeminiClient()

while true {
    print("> ", terminator: "")
    guard let cmd = readLine() else {
        break
    }

    if cmd.lowercased() == "q" {
        break
    }

    try handler.request(address: cmd)
}
