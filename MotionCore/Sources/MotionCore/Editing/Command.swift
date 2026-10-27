import Foundation

/// One edit to the project. Every change goes through a command so it can be undone.
public protocol Command {
    /// Shown in the interface, for example "Undo Move Layer".
    var name: String { get }
    /// Consecutive commands with the same key merge into one undo step
    /// (for example every tiny movement while a finger drags a layer).
    var coalescingKey: String? { get }
    /// Changes the project. Throw to refuse; the project is then left untouched.
    func apply(to project: inout Project) throws
}

extension Command {
    public var coalescingKey: String? { nil }
}
