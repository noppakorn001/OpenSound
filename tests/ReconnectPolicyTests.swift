import Foundation

@main struct ReconnectPolicyTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 100)
        var policy = ReconnectPolicy()
        assert(policy.consumeAttempt(now: now) == nil)
        policy.remember("test-device", wantsConnection: true, now: now)
        assert(policy.consumeAttempt(now: now.addingTimeInterval(1)) == nil)
        assert(policy.consumeAttempt(now: now.addingTimeInterval(2)) == "test-device")
        assert(policy.consumeAttempt(now: now.addingTimeInterval(2)) == nil)
        var current = now.addingTimeInterval(2)
        for delay in [5.0, 10, 20, 30, 60, 60, 60] {
            policy.disconnected(now: current)
            let expected = current.addingTimeInterval(delay)
            policy.disconnected(now: current.addingTimeInterval(1))
            assert(policy.nextAttempt == expected)
            assert(policy.consumeAttempt(now: expected.addingTimeInterval(-1)) == nil)
            assert(policy.consumeAttempt(now: expected) == "test-device")
            current = expected
        }
        policy.succeeded("test-device"); assert(policy.attempt == 0 && policy.nextAttempt == nil)
        policy.disconnected(now: current); policy.sleep()
        assert(policy.consumeAttempt(now: current.addingTimeInterval(1000)) == nil)
        policy.wake(now: current)
        assert(policy.consumeAttempt(now: current.addingTimeInterval(2)) == "test-device")
        policy.userDisconnected(); policy.disconnected(now: current); policy.wake(now: current)
        assert(policy.nextAttempt == nil)
        policy.remember("test-device", wantsConnection: true, now: current)
        policy.setEnabled(false, now: current)
        assert(policy.consumeAttempt(now: current.addingTimeInterval(100)) == nil)
        policy.setEnabled(true, now: current)
        assert(policy.consumeAttempt(now: current.addingTimeInterval(2)) == "test-device")
        policy.remember("", wantsConnection: true, now: current)
        assert(policy.nextAttempt == nil)
        print("Reconnect backoff, sleep/wake, retry coalescing, opt-out and manual-disconnect tests passed")
    }
}
