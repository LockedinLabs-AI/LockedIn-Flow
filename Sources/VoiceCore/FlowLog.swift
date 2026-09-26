import Foundation
import os.log

/// Content-free diagnostics. Interpolation accepts only numbers, booleans, and
/// numeric error codes; arbitrary strings and error descriptions cannot compile.
public enum FlowLog {
    public struct Message: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
        let rendered: String

        public init(stringLiteral value: StaticString) {
            rendered = String(describing: value)
        }

        public init(stringInterpolation: StringInterpolation) {
            rendered = stringInterpolation.rendered
        }

        public struct StringInterpolation: StringInterpolationProtocol {
            var rendered: String

            public init(literalCapacity: Int, interpolationCount: Int) {
                rendered = ""
                rendered.reserveCapacity(literalCapacity)
            }

            public mutating func appendLiteral(_ literal: StaticString) {
                rendered += String(describing: literal)
            }

            public mutating func appendInterpolation(_ value: Int) {
                rendered += String(value)
            }

            public mutating func appendInterpolation(_ value: Double) {
                rendered += String(value)
            }

            public mutating func appendInterpolation(_ value: Bool) {
                rendered += value ? "true" : "false"
            }

            public mutating func appendInterpolation(errorCode error: Error) {
                // Do not include the domain, description, userInfo, or paths.
                rendered += String((error as NSError).code)
            }
        }
    }

    private static let core = OSLog(
        subsystem: AppBuildIdentity.logSubsystem,
        category: "core"
    )
    private static let pipeline = OSLog(
        subsystem: AppBuildIdentity.logSubsystem,
        category: "pipeline"
    )

    public static func info(_ message: Message) {
        os_log("%{public}@", log: core, type: .info, message.rendered)
    }

    public static func error(_ message: Message) {
        os_log("%{public}@", log: core, type: .error, message.rendered)
    }

    public static func pipeline(_ message: Message) {
        os_log("%{public}@", log: pipeline, type: .debug, message.rendered)
    }
}
