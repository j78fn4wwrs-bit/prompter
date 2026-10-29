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
    /// Custom marker names, keyed by the marker's offset as a string ("120" -> "Intro take 2").
    /// Unnamed markers show as "Marker N". Optional so existing stores migrate (lightweight).
    var markerNames: [String: String]? = nil
    /// Marker timecodes in seconds, keyed like `markerNames`. Optional so existing stores migrate.
    var markerTimecodes: [String: Double]? = nil

    init(title: String, text: String) {
        self.title = title
        self.text = text
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Adds a marker at the start of the line containing `charOffset`.
    /// Returns the stored offset, or nil if a marker is already on that line.
    @discardableResult
    func addMarker(atLineContaining charOffset: Int) -> Int? {
        let ls = ScriptOutline.lines(text)
        let idx = ScriptOutline.lineIndex(for: charOffset, in: ls)
        guard ls.indices.contains(idx) else { return nil }
        let offset = ls[idx].startOffset
        var current = markerOffsets ?? []
        if current.contains(offset) { return nil }
        current.append(offset)
        current.sort()
        markerOffsets = current
        return offset
    }

    /// 1-based position of a marker among all markers, in script order.
    func markerNumber(for offset: Int) -> Int {
        ((markerOffsets ?? []).sorted().firstIndex(of: offset) ?? 0) + 1
    }

    func defaultMarkerName(for offset: Int) -> String { "Marker \(markerNumber(for: offset))" }

    /// Custom name if set, otherwise "Marker N".
    func markerName(for offset: Int) -> String {
        if let name = markerNames?[String(offset)], !name.isEmpty { return name }
        return defaultMarkerName(for: offset)
    }

    /// An empty name (or the default "Marker N") clears the custom name.
    func renameMarker(at offset: Int, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        var names = markerNames ?? [:]
        if trimmed.isEmpty || trimmed == defaultMarkerName(for: offset) {
            names[String(offset)] = nil
        } else {
            names[String(offset)] = trimmed
        }
        markerNames = names.isEmpty ? nil : names
    }

    func removeMarker(at offset: Int) {
        markerOffsets = (markerOffsets ?? []).filter { $0 != offset }
        if var names = markerNames {
            names[String(offset)] = nil
            markerNames = names.isEmpty ? nil : names
        }
        if var times = markerTimecodes {
            times[String(offset)] = nil
            markerTimecodes = times.isEmpty ? nil : times
        }
    }

    /// The timecode the user set for a marker, in seconds.
    func markerTimecode(for offset: Int) -> Double? { markerTimecodes?[String(offset)] }

    /// nil clears the timecode.
    func setMarkerTimecode(_ seconds: Double?, for offset: Int) {
        var times = markerTimecodes ?? [:]
        times[String(offset)] = seconds.map { max(0, $0) }
        markerTimecodes = times.isEmpty ? nil : times
    }

    /// Estimated time at the marker: words before it at the same pace as the "~0:37 read" estimate.
    func estimatedSeconds(for offset: Int, wordsPerMinute: Double = 150) -> Double {
        let prefix = String(text.prefix(max(0, offset)))
        let words = prefix.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        return (Double(words) / max(wordsPerMinute, 1)) * 60.0
    }

    /// Replaces the text and keeps markers (with names and timecodes) near the same words.
    /// Uses the common prefix/suffix of old and new text: markers before the change stay,
    /// markers after it shift by the length difference, markers inside it move to the change start.
    /// Each marker then snaps to the start of its line; two markers landing on one line merge.
    func replaceText(with newText: String) {
        let old = Array(text)
        let new = Array(newText)
        var prefix = 0
        while prefix < old.count && prefix < new.count && old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix && suffix < new.count - prefix
                && old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        let delta = new.count - old.count
        let oldChangeEnd = old.count - suffix

        let newLines = ScriptOutline.lines(newText)
        var newOffsets: [Int] = []
        var newNames: [String: String] = [:]
        var newTimes: [String: Double] = [:]
        for m in (markerOffsets ?? []).sorted() {
            var moved: Int
            if m < prefix {
                moved = m
            } else if m >= oldChangeEnd {
                moved = m + delta
            } else {
                moved = prefix
            }
            moved = min(max(0, moved), max(0, new.count))
            let li = ScriptOutline.lineIndex(for: moved, in: newLines)
            let snapped = newLines.indices.contains(li) ? newLines[li].startOffset : 0
            if newOffsets.contains(snapped) { continue }
            newOffsets.append(snapped)
            if let name = markerNames?[String(m)] { newNames[String(snapped)] = name }
            if let time = markerTimecodes?[String(m)] { newTimes[String(snapped)] = time }
        }
        text = newText
        updatedAt = Date()
        markerOffsets = newOffsets.isEmpty ? nil : newOffsets.sorted()
        markerNames = newNames.isEmpty ? nil : newNames
        markerTimecodes = newTimes.isEmpty ? nil : newTimes
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
    static func jumpPoints(lines: [ScriptLine], markers: [Int], names: [String: String] = [:]) -> [JumpPoint] {
        var points: [JumpPoint] = lines.filter { $0.headingLevel > 0 }.map {
            JumpPoint(id: "h\($0.id)", lineIndex: $0.id,
                      title: $0.text.isEmpty ? "Chapter" : $0.text, kind: .heading)
        }
        var markerNumber = 0
        for m in markers.sorted() {
            markerNumber += 1
            let li = lineIndex(for: m, in: lines)
            let preview = lines.indices.contains(li) ? String(lines[li].text.prefix(40)) : ""
            let title: String
            if let custom = names[String(m)], !custom.isEmpty {
                title = custom
            } else {
                title = "Marker \(markerNumber)" + (preview.isEmpty ? "" : ": \(preview)")
            }
            points.append(JumpPoint(id: "m\(m)", lineIndex: li, title: title, kind: .marker))
        }
        return points.sorted { $0.lineIndex == $1.lineIndex ? $0.kind == .heading : $0.lineIndex < $1.lineIndex }
    }
}
