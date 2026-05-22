import Foundation
import os

public struct APILogger: Sendable {
    private let logger: Logger

    public init(category: String) {
        self.logger = Logger(subsystem: "com.rareimagery.studio.api", category: category)
    }

    public func debug(_ message: String) { logger.debug("\(message, privacy: .public)") }
    public func info(_ message: String) { logger.info("\(message, privacy: .public)") }
    public func warning(_ message: String) { logger.warning("\(message, privacy: .public)") }
    public func error(_ message: String) { logger.error("\(message, privacy: .public)") }

    public func sensitive(_ message: String) { logger.debug("\(message, privacy: .private)") }
}
