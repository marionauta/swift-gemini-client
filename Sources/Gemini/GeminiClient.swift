import Foundation
import NIO
import NIOSSL

public class GeminiClient {
    private var rawResponse: String = ""
    private var lastResponse: Response? = nil

    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    private lazy var sslContext: NIOSSLContext = {
        var config = TLSConfiguration.forClient()
        config.certificateVerification = .none
        return try! NIOSSLContext(configuration: config)
    }()

    private lazy var bootstrap: ClientBootstrap = {
        return ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                let sslHandler = try! NIOSSLClientHandler(context: self.sslContext, serverHostname: nil)

                return channel.pipeline.addHandler(sslHandler).flatMap {
                    channel.pipeline.addHandlers(self, position: .after(sslHandler))
                }
            }
    }()

    deinit {
        try! group.syncShutdownGracefully()
    }

    public func request(address: String) throws {
        var cmd = address

        if !cmd.contains("://") {
            cmd = "gemini://" + cmd
        }

        guard let components = URLComponents(string: cmd) else {
            print("bad url")
            return
        }

        guard components.scheme == "gemini" else {
            print("Non gemini resource: \(components.string ?? "")")
            return
        }

        let port = components.port ?? 1965
        guard let host = components.host else {
            print("no host")
            return
        }

        let channel = try bootstrap.connect(host: host, port: port).wait()

        let request = "\(cmd)\r\n"
        var buffer = channel.allocator.buffer(capacity: request.utf8.count)
        buffer.writeString(request)
        try channel.writeAndFlush(buffer).wait()

        try channel.closeFuture.wait()

        if let response = lastResponse {
            try reactTo(response: response, originalRequest: cmd)
        }
    }

    private func reactTo(response: Response, originalRequest: String) throws {
        if response.isInput {
            print("Input: \(response.header.meta)")
            print("> ", terminator: "")
            let answer = readLine() ?? ""
            try request(address: "\(originalRequest)?\(answer)")

        } else if response.isRedirect {
            try request(address: response.header.meta)

        } else if response.isError {
            let message = "Error \(response.header.status): \(response.header.meta)"
            print(message)

        } else if response.isOk {
            print(response.body ?? ".")
        }
    }
}

// MARK: Channel Handler

extension GeminiClient: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)

        if let raw = buffer.readString(length: buffer.readableBytes) {
            rawResponse = rawResponse + raw
        }

        context.close(promise: nil)
    }

    public func channelInactive(context: ChannelHandlerContext) {
        if let response = Response(rawResponse) {
            rawResponse = ""
            lastResponse = response
        }

        context.close(promise: nil)
    }
}
