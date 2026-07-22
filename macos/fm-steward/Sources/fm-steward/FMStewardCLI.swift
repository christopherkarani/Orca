import Foundation
import FMSteward

// MARK: - CLI entry

// Phase 3 demo CLI: classify risk-card-v1 JSON via StewardSession.
// Default backend is UnavailableBackend; rules pre-pass covers fixture table
// without on-device Foundation Models. Timeout/unavailable → continue.

@main
enum FMStewardCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        do {
            let options = try Options.parse(args)
            switch options.command {
            case .help:
                printUsage()
                exit(0)
            case .classify(let cardPath, let timeoutMs, let human):
                try await runClassify(cardPath: cardPath, timeoutMs: timeoutMs, human: human)
            }
        } catch let error as CLIError {
            fputs("error: \(error.message)\n", stderr)
            if error.showUsage {
                fputs("\n", stderr)
                printUsage(to: stderr)
            }
            exit(error.exitCode)
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(2)
        }
    }
}

// MARK: - Commands

private enum Command {
    case help
    case classify(cardPath: String, timeoutMs: Int?, human: Bool)
}

private struct Options {
    var command: Command

    static func parse(_ args: [String]) throws -> Options {
        guard let first = args.first else {
            throw CLIError("missing command (try: classify --card <path.json>)", showUsage: true)
        }

        switch first {
        case "-h", "--help", "help":
            return Options(command: .help)
        case "classify":
            return try parseClassify(Array(args.dropFirst()))
        default:
            throw CLIError("unknown command '\(first)'", showUsage: true)
        }
    }

    private static func parseClassify(_ args: [String]) throws -> Options {
        var cardPath: String?
        var timeoutMs: Int?
        var human = false
        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "-h", "--help":
                return Options(command: .help)
            case "--card":
                i += 1
                guard i < args.count else {
                    throw CLIError("--card requires a path")
                }
                cardPath = args[i]
            case "--timeout-ms":
                i += 1
                guard i < args.count else {
                    throw CLIError("--timeout-ms requires an integer")
                }
                guard let value = Int(args[i]), value >= 0 else {
                    throw CLIError("--timeout-ms must be a non-negative integer (got '\(args[i])')")
                }
                timeoutMs = value
            case "--human":
                human = true
            case "--json":
                human = false
            default:
                if arg.hasPrefix("-") {
                    throw CLIError("unknown option '\(arg)'", showUsage: true)
                }
                // Positional card path (convenience).
                if cardPath == nil {
                    cardPath = arg
                } else {
                    throw CLIError("unexpected argument '\(arg)'", showUsage: true)
                }
            }
            i += 1
        }

        guard let cardPath else {
            throw CLIError("classify requires --card <path.json>", showUsage: true)
        }
        return Options(command: .classify(cardPath: cardPath, timeoutMs: timeoutMs, human: human))
    }
}

// MARK: - Classify

private func runClassify(cardPath: String, timeoutMs: Int?, human: Bool) async throws {
    let url = URL(fileURLWithPath: cardPath)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CLIError("card file not found: \(cardPath)", exitCode: 1)
    }

    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        throw CLIError("failed to read card: \(error.localizedDescription)", exitCode: 1)
    }

    let card: RiskCard
    do {
        let decoder = JSONDecoder()
        card = try decoder.decode(RiskCard.self, from: data)
    } catch {
        throw CLIError("invalid risk-card JSON: \(error.localizedDescription)", exitCode: 1)
    }

    // Default backend UnavailableBackend; rules pre-pass short-circuits fixture table.
    let session = StewardSession(timeoutMs: timeoutMs ?? StewardSession.defaultTimeoutMs)
    let response = await session.classify(card, timeoutMs: timeoutMs)

    if human {
        printHuman(response)
    } else {
        try printJSON(response)
    }
    // Classify success is always exit 0 (ask is a valid verdict, not a process error).
}

private func printJSON(_ response: ClassifyResponse) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    // Keep snake_case keys via CodingKeys on ClassifyResponse.
    let data = try encoder.encode(response)
    guard let text = String(data: data, encoding: .utf8) else {
        throw CLIError("failed to encode classify response as UTF-8", exitCode: 2)
    }
    print(text)
}

private func printHuman(_ response: ClassifyResponse) {
    print("verdict: \(response.verdict.rawValue)")
    print("why: \(response.why)")
    if let explain = response.explain, !explain.isEmpty {
        print("explain: \(explain)")
    }
    if response.timedOut {
        print("timed_out: true")
    }
    if response.fallback {
        print("fallback: true")
    }
    if let latency = response.latencyMs {
        print("latency_ms: \(latency)")
    }
}

// MARK: - Usage / errors

private struct CLIError: Error {
    let message: String
    let showUsage: Bool
    let exitCode: Int32

    init(_ message: String, showUsage: Bool = false, exitCode: Int32 = 2) {
        self.message = message
        self.showUsage = showUsage
        self.exitCode = exitCode
    }
}

private func printUsage(to stream: UnsafeMutablePointer<FILE> = stdout) {
    let text = """
    fm-steward — Mac-only Foundation Models steward demo CLI (Phase 3)

    Usage:
      fm-steward classify --card <path.json> [--timeout-ms N] [--json|--human]

    Options:
      --card <path>      Path to a risk-card-v1 JSON file (required)
      --timeout-ms N     Backend timeout in ms (default: \(StewardSession.defaultTimeoutMs))
      --json             Print classify-response-v1 JSON (default)
      --human            Print compact verdict / why / explain lines
      -h, --help         Show this help

    Notes:
      - Default backend is unavailable; deterministic rules pre-pass handles fixtures.
      - Timeout or unavailable model → verdict continue (fallback), never hang.
      - Production Zig hook wiring (W4) is NOT done in Phase 3.
    """
    fputs(text + "\n", stream)
}
