import Foundation
import SwiftData

@Model
final class Script {
    var title: String
    var text: String
    var createdAt: Date
    var updatedAt: Date

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
    Welcome to Prompter.

    Tap the screen to start or pause. After a 3-2-1 countdown, your words scroll up past the reading line.

    Drag up or down while paused to move through the script. Use the slider to change the speed and the size of the text.

    Turn on Mirror if you are reading through a beam-splitter glass.

    That's it. Paste in your own script and go.
    """
}
