import Foundation
import LearningCore
let queue = ObservationQueue()
let entry = LexiconEntry(type: .unicode, reading: "sio2", text: "SiO₂")
let event = Observation(entry: entry, kind: .autoCommitted)
var durations: [Double] = []
for i in 0..<100_000 {
    if i % 128 == 0 { _ = queue.drain() }
    let start = DispatchTime.now().uptimeNanoseconds
    _ = queue.offer(event)
    durations.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
}
durations.sort()
print("ObservationQueue only; not IMK key latency. samples=100000 P50=\(durations[50000])ms P95=\(durations[95000])ms P99=\(durations[99000])ms")

let full = ObservationQueue(capacity: 1)
_ = full.offer(event)
var rejected: [Double] = []
for _ in 0..<100_000 {
    let start = DispatchTime.now().uptimeNanoseconds
    _ = full.offer(event)
    rejected.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
}
rejected.sort()
print("Full queue / stalled consumer; samples=100000 P50=\(rejected[50000])ms P95=\(rejected[95000])ms P99=\(rejected[99000])ms")
