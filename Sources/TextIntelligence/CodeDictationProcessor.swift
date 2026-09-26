import Foundation

/// Code-mode dictation processing: spoken symbols, case commands, and layout controls
/// for dictating into editors, terminals, and AI coding assistants.
///
///   "function camel case get user name open paren close paren open brace"
///     →  function getUserName() {
///   "snake case max retry count"   →  max_retry_count
///   "constant case max retries"    →  MAX_RETRIES
public struct CodeDictationProcessor: Sendable {
    public init() {}

    // MARK: Symbol map (longest phrase first)

    static let symbolPhrases: [(phrase: [String], symbol: String)] = [
        (["open", "parenthesis"], "("), (["close", "parenthesis"], ")"),
        (["open", "paren"], "("), (["close", "paren"], ")"),
        (["open", "brace"], "{"), (["close", "brace"], "}"),
        (["open", "bracket"], "["), (["close", "bracket"], "]"),
        (["open", "angle"], "<"), (["close", "angle"], ">"),
        (["fat", "arrow"], "=>"), (["arrow"], "->"),
        (["single", "quote"], "'"), (["double", "quote"], "\""),
        (["forward", "slash"], "/"), (["backslash"], "\\"), (["slash"], "/"),
        (["question", "mark"], "?"), (["exclamation", "point"], "!"),
        (["semicolon"], ";"), (["colon"], ":"), (["comma"], ","), (["period"], "."),
        (["underscore"], "_"), (["backtick"], "`"), (["tilde"], "~"),
        (["ampersand"], "&"), (["pipe"], "|"), (["caret"], "^"),
        (["hash"], "#"), (["hashtag"], "#"),
        (["at", "sign"], "@"), (["dollar", "sign"], "$"), (["percent", "sign"], "%"),
        (["asterisk"], "*"), (["star"], "*"),
        (["equals", "equals"], "=="), (["equals"], "="),
        (["plus", "plus"], "++"), (["plus"], "+"), (["minus"], "-"),
        (["less", "than"], "<"), (["greater", "than"], ">"),
        (["new", "line"], "\n"), (["tab"], "\t"),
        (["no", "space"], "␣"),
    ]

    /// Attaches to the following piece (no space after).
    static let openers: Set<String> = ["{", "<", "@", "$", "#", "~"]
    /// Attaches to the previous piece (no space before).
    static let closers: Set<String> = [")", "]", "}", ";", ":", ",", "?", "!", ">", "%"]
    /// Attaches on both sides (no spaces either way).
    static let joiners: Set<String> = [
        "->", "=>", "=", "==", "+", "++", "-", "*", "/", "\\", "&", "|", "^", "_", ".",
    ]
    /// Attaches to the previous piece AND the following one: `getUser()`.
    static let attachBoth: Set<String> = ["(", "["]
    /// Quote marks: alternate open/close state in `join`.
    static let quotes: Set<String> = ["\"", "'", "`"]

    // MARK: Case commands

    public enum CaseCommand: String, CaseIterable, Sendable {
        case camel = "camel case"
        case pascal = "pascal case"
        case snake = "snake case"
        case constant = "constant case"
        case kebab = "kebab case"
    }

    /// Applies case commands, then symbol replacement, to a raw utterance.
    public func process(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        text = applyCaseCommands(to: text)
        text = applySymbols(to: text)
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " "))
    }

    // MARK: Case commands

    func applyCaseCommands(to text: String) -> String {
        // Identifier words end at the next symbol phrase, layout keyword, or punctuation.
        let symbolAlternation = Self.symbolPhrases
            .map { $0.phrase.joined(separator: " ") }
            .sorted { $0.count > $1.count }
            .map {
                NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(
                    of: "\\ ", with: "\\s+")
            }
            .joined(separator: "|")
        var result = text
        for command in CaseCommand.allCases {
            let head = command.rawValue.replacingOccurrences(of: " ", with: #"\s+"#)
            let pattern =
                #"\b"# + head + #"\s+([^.,\n]+?)(?=\s+(?:"# + symbolAlternation + #")\b|[.,\n]|$)"#
            guard
                let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            else { continue }
            let matches = regex.matches(
                in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                    let wordsRange = Range(match.range(at: 1), in: result)
                else { continue }
                let words = String(result[wordsRange])
                let transformed = transform(words: words, command: command)
                result.replaceSubrange(fullRange, with: transformed)
            }
        }
        return result
    }

    func transform(words: String, command: CaseCommand) -> String {
        let parts =
            words
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return words }
        switch command {
        case .camel:
            return parts[0] + parts.dropFirst().map(\.capitalized).joined()
        case .pascal:
            return parts.map(\.capitalized).joined()
        case .snake:
            return parts.joined(separator: "_")
        case .constant:
            return parts.joined(separator: "_").uppercased()
        case .kebab:
            return parts.joined(separator: "-")
        }
    }

    // MARK: Symbols

    func applySymbols(to text: String) -> String {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var pieces: [String] = []
        var i = 0
        while i < tokens.count {
            var matched = false
            for entry in Self.symbolPhrases {
                let count = entry.phrase.count
                guard i + count <= tokens.count else { continue }
                let slice = tokens[i..<(i + count)].map {
                    $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!?"))
                }
                if slice == entry.phrase {
                    pieces.append(entry.symbol)
                    i += count
                    matched = true
                    break
                }
            }
            if !matched {
                // Spoken numbers become digits in code mode ("five" → "5").
                let token = tokens[i]
                pieces.append(Self.numberWords[token.lowercased()] ?? token)
                i += 1
            }
        }
        return join(pieces: pieces)
    }

    static let numberWords: [String: String] = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
        "ten": "10", "eleven": "11", "twelve": "12", "thirteen": "13",
        "fourteen": "14", "fifteen": "15", "sixteen": "16", "seventeen": "17",
        "eighteen": "18", "nineteen": "19", "twenty": "20",
    ]

    func join(pieces: [String]) -> String {
        var output = ""
        var attachNext = false
        var openQuote: String?

        for piece in pieces {
            if piece == "␣" {  // "no space"
                attachNext = true
                continue
            }

            if Self.quotes.contains(piece) {
                if openQuote == piece {
                    output += piece  // closing quote: attach left
                    openQuote = nil
                    attachNext = false
                } else {
                    // opening quote: space before, unless start / opener / joiner / layout
                    let attach =
                        output.isEmpty || attachNext
                        || output.hasSuffix("\n") || output.hasSuffix("\t")
                        || Self.openers.contains(String(output.last!))
                        || Self.joiners.contains(String(output.last!))
                        || Self.attachBoth.contains(String(output.last!))
                    output += attach ? piece : " " + piece
                    openQuote = piece
                    attachNext = true
                }
                continue
            }

            if piece == "\n" || piece == "\t" {
                output = output.trimmingCharacters(in: CharacterSet(charactersIn: " "))
                output += piece
                attachNext = true
                continue
            }

            if output.isEmpty {
                output = piece
                attachNext =
                    Self.openers.contains(piece) || Self.joiners.contains(piece)
                    || Self.attachBoth.contains(piece)
                continue
            }

            let previous = String(output.last!)
            let attach =
                attachNext
                || Self.closers.contains(piece)
                || Self.joiners.contains(piece)
                || Self.attachBoth.contains(piece)
                || Self.openers.contains(previous)
                || openQuote == previous
                || output.hasSuffix("\n")
                || output.hasSuffix("\t")

            output += attach ? piece : " " + piece
            attachNext =
                Self.openers.contains(piece) || Self.joiners.contains(piece)
                || Self.attachBoth.contains(piece)
        }
        return output
    }
}
