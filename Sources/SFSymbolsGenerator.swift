//
//  SFSymbolsGenerator.swift
//  SFSymbolsGenerator
//
//  Created by Leo Ho on 2023/10/27.
//

import ArgumentParser
import Foundation

enum OutputMode: String, CaseIterable, ExpressibleByArgument {
    case `enum`
    case `struct`
}

@main
struct SFSymbolsGenerator: ParsableCommand {

    static let configuration = CommandConfiguration(
        abstract: "Simplifying SF Symbols Enumeration Generation with Swift!",
        version: "1.2.0"
    )

    @Argument(
        help: "[Required] Specify filepath of output. Example: /Users/<YOUR_USERNAME>/Desktop"
    )
    var filepath: String

    @Option(
        name: .customLong("name"),
        help: "[Optional] Specify filename of output. Example: SFSymbols+Enum"
    )
    var filename: String = "SFSymbols+Enum"

    @Flag(
        name: [.customLong("use-beta")],
        help: "Whether use beta version of SF Symbols or not."
    )
    var isUseBeta: Bool = false

    @Option(
        name: .customLong("mode"),
        help: "Output mode: 'enum' generates an enum with CaseIterable (may cause OOM on Swift 6+), 'struct' generates a struct with static constants (recommended for Swift 6+)."
    )
    var outputMode: OutputMode = .enum

    mutating func run() throws {
        do {
            var appURL: URL!
            if isUseBeta {
                appURL = URL(fileURLWithPath: "/Applications/SF Symbols beta.app/Contents/Resources/Metadata/name_availability.plist")
            } else {
                appURL = URL(fileURLWithPath: "/Applications/SF Symbols.app/Contents/Resources/Metadata/name_availability.plist")
            }

            let (sortedSymbolTuple, releaseYears) = try readSymbolsAndYears(from: appURL)

            let outputStream = OutputStreamCapture()

            switch outputMode {
            case .enum:
                generateEnum(sortedSymbolTuple: sortedSymbolTuple, releaseYears: releaseYears, outputStream: outputStream)
            case .struct:
                generateStruct(sortedSymbolTuple: sortedSymbolTuple, releaseYears: releaseYears, outputStream: outputStream)
            }

            let writer = FileWriter()
            writer.write(with: outputStream.capturedOutput, and: filename, to: filepath)
        } catch (let error as GenerateError) {
            switch error {
            case .unknown(_), .propertyList(_):
                print(error.description)
            case .notInstallSFSymbols, .notInstallSFSymbolsBeta:
                print("Error：\(error.description)")
            }
        }
    }

    // MARK: - Enum Mode (original behavior)

    private func generateEnum(sortedSymbolTuple: [SymbolTuple], releaseYears: Releases, outputStream: OutputStreamCapture) {
        outputStream.capturePrint(
    """
    import Foundation

    extension SFSymbol {
        public enum SystemSymbolName: String, CaseIterable, SymbolName {\n
    """
        )

        for symbolTuple in sortedSymbolTuple {
            outputStream.capturePrint("        " + "/// SF Symbols's name：" + symbolTuple.symbol)
            outputStream.capturePrint("        @" + releaseYears[symbolTuple.released]!.availabilty + "\n        case " + symbolTuple.symbol.replacementName + " = \"" + symbolTuple.symbol + "\"\n" )
        }
        outputStream.capturePrint(
    """
            public static var allCases: [Self] {
                var allCases: [Self] = []\n
    """
        )

        for symbolTuple in sortedSymbolTuple {
            outputStream.capturePrint("            if #" + releaseYears[symbolTuple.released]!.availabilty + " {\n                allCases.append(Self." + symbolTuple.symbol.replacementName + ")\n            }\n")
        }
        outputStream.capturePrint(
    """
                return allCases
            }
        }
    }
    """
        )
    }

    // MARK: - Struct Mode (avoids Swift 6 compiler OOM)

    private func generateStruct(sortedSymbolTuple: [SymbolTuple], releaseYears: Releases, outputStream: OutputStreamCapture) {
        outputStream.capturePrint(
    """
    import Foundation

    extension SFSymbol {
        public struct SystemSymbolName: RawRepresentable, Hashable, Sendable, SymbolName {
            public let rawValue: String
            public init(rawValue: String) {
                self.rawValue = rawValue
            }
        }
    }

    extension SFSymbol.SystemSymbolName {\n
    """
        )

        for symbolTuple in sortedSymbolTuple {
            outputStream.capturePrint("    /// SF Symbols's name：" + symbolTuple.symbol)
            outputStream.capturePrint("    @" + releaseYears[symbolTuple.released]!.availabilty + "\n    public static let " + symbolTuple.symbol.replacementName + " = Self(rawValue: \"" + symbolTuple.symbol + "\")\n")
        }

        outputStream.capturePrint("}")
    }

    // MARK: - Plist Parsing

    private func readSymbolsAndYears(from fileURL: URL) throws -> ([SymbolTuple], Releases) {
        do {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            do {
                let propertyList = try PropertyListSerialization.propertyList(from: data,
                                                                              options: [],
                                                                              format: nil) as! Dictionary<String, Any>

                let symbols = propertyList["symbols"] as! Symbols
                let releases = propertyList["year_to_release"] as! Releases

                let releaseDatesFromSymbols = Set<ReleaseDate>(symbols.values)
                let releaseDatesFromReleases = Set<ReleaseDate>(releases.keys)

                assert(releaseDatesFromReleases.isSubset(of:releaseDatesFromSymbols),
                       "There are symbols with releasedates that have no release versions \(releaseDatesFromReleases) < \(releaseDatesFromSymbols)")

                let sortedSymbolTuple = symbols
                    .sorted {
                        $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value
                    }
                    .map {
                        SymbolTuple(symbol: $0.key, released: $0.value)
                    }

                return (sortedSymbolTuple, releases)
            } catch {
                throw GenerateError.propertyList(error)
            }
        } catch {
            if fileURL.path().contains("SF%20Symbols.app") {
                throw GenerateError.notInstallSFSymbols
            } else if fileURL.path().contains("SF%20Symbols%20beta.app") {
                throw GenerateError.notInstallSFSymbolsBeta
            } else {
                throw GenerateError.unknown(error)
            }
        }
    }
}
