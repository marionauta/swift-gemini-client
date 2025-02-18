import Foundation
import NIO
import NIOSSL

public class GeminiClient {
    private var rawResponse: Data?
    private var lastResponse: GeminiResponse? = nil

    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    private lazy var sslContext: NIOSSLContext = {
        var config = TLSConfiguration.makeClientConfiguration()
        config.certificateVerification = .none
        return try! NIOSSLContext(configuration: config)
    }()

    private lazy var bootstrap: NIOClientTCPBootstrap = {
        let tlsProvider = try! NIOSSLClientTLSProvider<ClientBootstrap>(context: sslContext, serverHostname: nil)
        return NIOClientTCPBootstrap(ClientBootstrap(group: group), tls: tlsProvider).enableTLS()
            .channelInitializer { channel in
                return channel.pipeline.addHandler(self, name: "gemini")
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

    private func reactTo(response: GeminiResponse, originalRequest: String) throws {
        if response.isInput {
            print("Input: \(response.header.meta)")
            print("> ", terminator: "")
            let answer = readLine() ?? ""
            try request(address: "\(originalRequest)?\(answer)")

        } else if response.isRedirect {
            if response.header.meta.isEmpty {
                print("ERROR: Invalid redirect (empty)")
            } else {
                try request(address: response.header.meta)
            }

        } else if response.isError {
            let message = "ERROR: (\(response.header.status)) \(response.header.meta)"
            print(message)

        } else if response.isOk, let body = response.body, let body = String(data: body, encoding: .utf8) {
            print(body)
        }
    }
}

// MARK: Channel Handler

extension GeminiClient: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)

        if let raw = buffer.readBytes(length: buffer.readableBytes) {
            if let rawResponse {
                self.rawResponse = rawResponse + raw
            } else {
                self.rawResponse = Data(raw)
            }
        }

        context.close(promise: nil)
    }

    public func channelInactive(context: ChannelHandlerContext) {
        if let raw = rawResponse, let response = GeminiResponse(raw) {
            rawResponse = nil
            lastResponse = response
        }

        context.close(promise: nil)
    }
}
