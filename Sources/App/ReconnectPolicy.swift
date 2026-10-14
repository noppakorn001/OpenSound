import Foundation

// Pure scheduling state, independent of Bluetooth and UI. Retries only target
// a device the user previously selected, and never restore sound settings.
struct ReconnectPolicy {
    var enabled = true
    private(set) var target = ""
    private(set) var wantsConnection = false
    private(set) var sleeping = false
    private(set) var attempt = 0
    private(set) var nextAttempt: Date?

    mutating func remember(_ address: String, wantsConnection: Bool, now: Date) {
        target = address; self.wantsConnection = wantsConnection
        attempt = 0; nextAttempt = nil
        if wantsConnection { disconnected(now: now) }
    }
    mutating func succeeded(_ address: String) {
        target = address; wantsConnection = true; attempt = 0; nextAttempt = nil
    }
    mutating func userDisconnected() {
        wantsConnection = false; attempt = 0; nextAttempt = nil
    }
    mutating func disconnected(now: Date) {
        guard enabled, wantsConnection, !sleeping, !target.isEmpty, nextAttempt == nil else { return }
        let delays: [TimeInterval] = [2, 5, 10, 20, 30, 60]
        nextAttempt = now.addingTimeInterval(delays[min(attempt, delays.count - 1)])
        attempt = min(attempt + 1, delays.count - 1)
    }
    mutating func setEnabled(_ enabled: Bool, now: Date) {
        self.enabled = enabled; nextAttempt = nil; attempt = 0
        if enabled { disconnected(now: now) }
    }
    mutating func sleep() { sleeping = true; nextAttempt = nil }
    mutating func wake(now: Date) { sleeping = false; attempt = 0; disconnected(now: now) }
    mutating func consumeAttempt(now: Date) -> String? {
        guard enabled, wantsConnection, !sleeping, let due = nextAttempt, due <= now else { return nil }
        nextAttempt = nil
        return target
    }
}
