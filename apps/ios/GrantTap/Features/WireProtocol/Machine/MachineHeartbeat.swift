import Foundation

/// Cheap liveness evidence from the machine publisher.
///
/// The catalog cannot carry this: scanning every provider transcript is
/// unbounded work, so a healthy-but-busy computer would look dead and the phone
/// would purge its chat list. This arrives on its own fixed cadence instead.
struct MachineHeartbeat: Decodable {
    let type: String
    let machine: String
    let createdAt: Double
    let taskQueueImmediate: Bool?

    enum CodingKeys: String, CodingKey {
        case type, machine, createdAt, taskQueueImmediate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? container.decode(String.self, forKey: .type)) ?? "machine.heartbeat"
        machine = (try? container.decode(String.self, forKey: .machine)) ?? ""
        createdAt = (try? container.decode(Double.self, forKey: .createdAt)) ?? 0
        taskQueueImmediate = try? container.decode(Bool.self, forKey: .taskQueueImmediate)
    }

    init(machine: String, createdAt: Double, taskQueueImmediate: Bool? = nil) {
        self.type = "machine.heartbeat"
        self.machine = machine
        self.createdAt = createdAt
        self.taskQueueImmediate = taskQueueImmediate
    }
}
