import Foundation

func formatDuration(_ start: Date, _ end: Date) -> String {
    let minutes = Int(end.timeIntervalSince(start) / 60)
    guard minutes > 0 else { return "< 1m" }
    if minutes < 60 { return "\(minutes)m" }
    return "\(minutes / 60)h \(minutes % 60)m"
}

func formattedDate(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
}
