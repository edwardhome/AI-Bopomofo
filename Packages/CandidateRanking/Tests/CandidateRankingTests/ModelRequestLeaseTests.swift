import Foundation
import Testing
@testable import CandidateRanking

@Suite struct ModelRequestLeaseTests {
    @Test func cancellationDoesNotReleaseHungInference() {
        var lease = ModelRequestLease(); let first = UUID(), second = UUID()
        let started = lease.begin(first); #expect(started)
        lease.cancel(); #expect(!lease.canStart)
        let overlap = lease.begin(second); #expect(!overlap)
        let lateWrong = lease.finish(second); #expect(!lateWrong)
        #expect(!lease.canStart)
        let done = lease.finish(first); #expect(done); #expect(lease.canStart)
    }
    @Test func lateReplyAfterDisconnectCannotFinishNewRequest() {
        var lease = ModelRequestLease(); let first = UUID(), second = UUID()
        _ = lease.begin(first); lease.disconnect(); _ = lease.begin(second)
        let late = lease.finish(first); #expect(!late); #expect(!lease.canStart)
        let done = lease.finish(second); #expect(done)
    }
}
