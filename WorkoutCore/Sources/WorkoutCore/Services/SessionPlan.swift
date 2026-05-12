import Foundation

public struct SessionPlan: Equatable, Hashable, Identifiable, Sendable {
    public struct Exercise: Equatable, Hashable, Sendable {
        public let name: String
        public let kind: ExerciseKind
        public let sets: [Set]

        public init(name: String, kind: ExerciseKind, sets: [Set]) {
            self.name = name
            self.kind = kind
            self.sets = sets
        }
    }

    public struct Set: Equatable, Hashable, Sendable {
        public let targetWeightKg: Double?
        public let targetReps: Int?
        public let targetDurationSec: Int?
        public let targetDistanceM: Double?
        public let restSec: Int

        public init(
            targetWeightKg: Double? = nil,
            targetReps: Int? = nil,
            targetDurationSec: Int? = nil,
            targetDistanceM: Double? = nil,
            restSec: Int
        ) {
            self.targetWeightKg = targetWeightKg
            self.targetReps = targetReps
            self.targetDurationSec = targetDurationSec
            self.targetDistanceM = targetDistanceM
            self.restSec = restSec
        }
    }

    public let templateID: UUID?
    public let templateName: String
    public let exercises: [Exercise]

    public init(templateID: UUID? = nil, templateName: String, exercises: [Exercise]) {
        self.templateID = templateID
        self.templateName = templateName
        self.exercises = exercises
    }

    public var isEmpty: Bool {
        exercises.allSatisfy { $0.sets.isEmpty }
    }

    public var id: String {
        templateID?.uuidString ?? templateName + "-" + String(exercises.count)
    }
}

public struct SetCursor: Equatable, Sendable, Hashable {
    public let exerciseIndex: Int
    public let setIndex: Int

    public init(exerciseIndex: Int, setIndex: Int) {
        self.exerciseIndex = exerciseIndex
        self.setIndex = setIndex
    }
}

public extension SessionPlan {
    func exercise(at cursor: SetCursor) -> Exercise? {
        guard exercises.indices.contains(cursor.exerciseIndex) else { return nil }
        return exercises[cursor.exerciseIndex]
    }

    func set(at cursor: SetCursor) -> Set? {
        guard let ex = exercise(at: cursor),
              ex.sets.indices.contains(cursor.setIndex) else { return nil }
        return ex.sets[cursor.setIndex]
    }

    /// Returns the cursor that follows `cursor`, paired with whether the next
    /// step crosses an exercise boundary (true => prep, false => rest).
    /// Returns nil if `cursor` is the final set in the plan.
    func successor(of cursor: SetCursor) -> (next: SetCursor, crossesExercise: Bool)? {
        guard let ex = exercise(at: cursor) else { return nil }
        let nextSetIdx = cursor.setIndex + 1
        if nextSetIdx < ex.sets.count {
            return (SetCursor(exerciseIndex: cursor.exerciseIndex, setIndex: nextSetIdx), false)
        }
        var nextExerciseIdx = cursor.exerciseIndex + 1
        while nextExerciseIdx < exercises.count {
            if !exercises[nextExerciseIdx].sets.isEmpty {
                return (SetCursor(exerciseIndex: nextExerciseIdx, setIndex: 0), true)
            }
            nextExerciseIdx += 1
        }
        return nil
    }

    var firstCursor: SetCursor? {
        for (idx, ex) in exercises.enumerated() where !ex.sets.isEmpty {
            return SetCursor(exerciseIndex: idx, setIndex: 0)
        }
        return nil
    }
}
