import Foundation

public enum Duration {
    /// Parses `90`, `90m`, `2h`, `1h30m` into minutes. Bare numbers are minutes.
    public static func minutes(_ text: String) -> Int? {
        let s = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }
        if let n = Int(s) { return n > 0 ? n : nil }
        var total = 0, number = "", sawUnit = false
        for ch in s {
            if ch.isNumber {
                number.append(ch)
            } else if ch == "h" || ch == "m" {
                guard let n = Int(number) else { return nil }
                total += ch == "h" ? n * 60 : n
                number = ""
                sawUnit = true
            } else {
                return nil
            }
        }
        guard number.isEmpty, sawUnit, total > 0 else { return nil }
        return total
    }

    /// `1h 05m`, `12m`, `45s`.
    public static func format(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds < 60 { return "\(seconds)s" }
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h > 0 ? String(format: "%dh %02dm", h, m) : "\(m)m"
    }
}
