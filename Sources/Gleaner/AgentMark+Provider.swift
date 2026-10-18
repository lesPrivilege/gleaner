import GleanerCore
import GleanerUI
import SwiftUI

extension AgentMark.Agent {
    /// The agent whose logs `provider` names.
    init(_ provider: Provider) {
        switch provider {
        case .claudeCode: self = .claudeCode
        case .codex: self = .codex
        }
    }
}

extension AgentMark {
    /// The mark of the agent whose logs a delivery came from.
    init(provider: Provider, size: CGFloat = 14, color: Bool = false) {
        self.init(Agent(provider), size: size, color: color)
    }
}
