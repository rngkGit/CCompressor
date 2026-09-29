import Foundation

public protocol FileCompressorProtocol: Sendable {
    func compress(
        inputURL: URL,
        outputURL: URL,
        quality: Double,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws
}
