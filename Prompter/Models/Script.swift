import Foundation
import SwiftData

@Model
final class Script {
    var title: String
    var text: String
    var createdAt: Date
    var updatedAt: Date
    /// Live-run markers, stored as character offsets into `text`.
    /// Optional with a default so existing stores migrate automatically (lightweight).
    var markerOffsets: [Int]? = nil

    init(title: String, text: String) {
        self.title = title
        self.text = text
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Estimated read time at a speaking pace (words per minute).
    func readTime(wordsPerMinute: Double = 150) -> String {
        let seconds = Int((Double(wordCount) / max(wordsPerMinute, 1)) * 60.0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static let sampleText = """
    # Welcome to Steady Prompter

    Tap the screen to start or pause. After a 3-2-1 countdown, your words scroll up past the reading line.

    Drag up or down while paused to move through the script. Use the sliders to change the speed and the size of the text.

    ## Chapters

    Start a line with # or ## to make it a chapter. Tap the list button while prompting to jump to any chapter.

    Turn on Mirror if you are reading through a beam-splitter glass.

    That's it. Paste in your own script and go.
    """
}

/// One displayed line of a script, with its chapter/marker info.
struct ScriptLine: Identifiable {
    let id: Int
    let startOffset: Int
    let text: String
    let headingLevel: Int   // 0 = normal line
}

struct JumpPoint: Identifiable {
    enum Kind { case heading, marker }
    let id: String
    let lineIndex: Int
    let title: String
    let kind: Kind
}

enum ScriptOutline {
    static func lines(_ text: String) -> [ScriptLine] {
        var result: [ScriptLine] = []
        var offset = 0
        for (i, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(raw)
            var level = 0
            var display = line
            let trimmed = line.drop(while: { $0 == " " })
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" }).count
                let rest = trimmed.dropFirst(hashes)
                if hashes <= 6, rest.isEmpty || rest.first == " " {
                    level = hashes
                    display = rest.trimmingCharacters(in: .whitespaces)
                }
            }
            result.append(ScriptLine(id: i, startOffset: offset, text: display, headingLevel: level))
            offset += line.count + 1
        }
        return result
    }

    /// Index of the line containing a character offset.
    static func lineIndex(for charOffset: Int, in lines: [ScriptLine]) -> Int {
        var idx = 0
        for line in lines where line.startOffset <= charOffset { idx = line.id }
        return idx
    }

    /// Headings plus saved markers, in script order.
    static func jumpPoints(lines: [ScriptLine], markers: [Int]) -> [JumpPoint] {
        var points: [JumpPoint] = lines.filter { $0.headingLevel > 0 }.map {
            JumpPoint(id: "h\($0.id)", lineIndex: $0.id,
                      title: $0.text.isEmpty ? "Chapter" : $0.text, kind: .heading)
        }
        var markerNumber = 0
        for m in markers.sorted() {
            markerNumber += 1
            let li = lineIndex(for: m, in: lines)
            let preview = lines.indices.contains(li) ? String(lines[li].text.prefix(40)) : ""
            points.append(JumpPoint(id: "m\(m)", lineIndex: li,
                                    title: "Marker \(markerNumber)" + (preview.isEmpty ? "" : ": \(preview)"),
                                    kind: .marker))
        }
        return points.sorted { $0.lineIndex == $1.lineIndex ? $0.kind == .heading : $0.lineIndex < $1.lineIndex }
    }
}
