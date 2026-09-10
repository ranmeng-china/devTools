import Foundation

/// 规则解析层的本地执行边界；不读取外部资源，也不执行网络请求。
struct LocalRuleParser {
    func validateInput(_ text: String) -> RuleInputValidation {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .acceptable
    }
}

enum RuleInputValidation: Equatable {
    case empty
    case acceptable
}
