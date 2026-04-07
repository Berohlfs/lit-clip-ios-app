import Foundation

struct VideoClip: Identifiable {
    let id: UUID
    let url: URL
    let createdAt: Date
    let duration: TimeInterval

    init(url: URL, duration: TimeInterval) {
        self.id = UUID()
        self.url = url
        self.createdAt = Date()
        self.duration = duration
    }
}
