import Foundation

struct XrayReleaseChoice: Identifiable, Hashable, Sendable {
    var id: Int { number }
    var number: Int
    var version: String
}

enum XrayReleaseParser {
    nonisolated static func parseChoices(from output: String) -> [XrayReleaseChoice] {
        let pattern = #"(?m)^\s*(\d+)\.\s*(v?[0-9][0-9A-Za-z.\-_]*)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)

        return regex.matches(in: output, range: range).compactMap { match in
            guard match.numberOfRanges == 3,
                  let numberRange = Range(match.range(at: 1), in: output),
                  let versionRange = Range(match.range(at: 2), in: output),
                  let number = Int(output[numberRange])
            else {
                return nil
            }

            return XrayReleaseChoice(number: number, version: String(output[versionRange]))
        }
    }
}
