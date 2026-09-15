import Foundation
import SwiftData

/// V3 adds the pieces the progression coach needs:
///
/// - `PerformedSet.exerciseID` — the Lift Identity. Performed history matches on the
///   exercise's stable id rather than its display name, so a rename no longer splits a
///   lift's history and two same-named exercises are no longer pooled. See
///   `docs/adr/0001-exercise-identity-in-performed-history.md`.
/// - `PerformedSet.target*` — the Target that was actually in effect when the set was
///   performed. The coach writes proposals onto `PlannedSet`, so the workout's targets
///   move over time; without this, a past Session's "planned vs done" would silently
///   re-render against today's numbers.
/// - `PerformedSet.suggested*` — what the Coach proposed for that set, which differs from
///   the Target whenever a proposal is still pending review or the lifter overrode it.
///   This deviation signal is the only way to tell whether the coach is any good.
/// - `Exercise.progressionStep` — the Progression Step, in the unit of that exercise's
///   Progression Dimension. Nil means "use the default for this kind".
/// - `ProposedTarget` — a Proposed Target held for review. Only proposals that need a
///   human (deloads, repeat stalls, anything larger than one step) are stored; single-step
///   moves are applied straight to `PlannedSet` and never land here.
public enum WorkoutSchemaV3: VersionedSchema {
    public static var versionIdentifier = Schema.Version(3, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Exercise.self,
            PlannedSet.self,
            PlannedExercise.self,
            WorkoutTemplate.self,
            WorkoutSession.self,
            PerformedSet.self,
            ProposedTarget.self
        ]
    }

    @Model
    public final class Exercise {
        @Attribute(.unique) public var id: UUID
        public var name: String
        public var kindRaw: String
        public var defaultRestSec: Int
        public var defaultTargetReps: Int?
        public var defaultTargetDurationSec: Int?
        public var defaultTargetDistanceM: Double?
        /// Smallest meaningful increase along this exercise's Progression Dimension, in
        /// that dimension's own unit. Nil falls back to `ProgressionDimension.defaultStep`.
        public var progressionStep: Double?

        public var kind: ExerciseKind {
            get { ExerciseKind(rawValue: kindRaw) ?? .reps }
            set { kindRaw = newValue.rawValue }
        }

        public init(
            id: UUID = UUID(),
            name: String,
            kind: ExerciseKind,
            defaultRestSec: Int,
            defaultTargetReps: Int? = nil,
            defaultTargetDurationSec: Int? = nil,
            defaultTargetDistanceM: Double? = nil,
            progressionStep: Double? = nil
        ) {
            self.id = id
            self.name = name
            self.kindRaw = kind.rawValue
            self.defaultRestSec = defaultRestSec
            self.defaultTargetReps = defaultTargetReps
            self.defaultTargetDurationSec = defaultTargetDurationSec
            self.defaultTargetDistanceM = defaultTargetDistanceM
            self.progressionStep = progressionStep
        }
    }

    @Model
    public final class PlannedSet {
        @Attribute(.unique) public var id: UUID
        public var orderIndex: Int
        public var targetWeightKg: Double?
        public var targetReps: Int?
        public var targetDurationSec: Int?
        public var targetDistanceM: Double?
        public var plannedExercise: PlannedExercise?

        public init(
            id: UUID = UUID(),
            orderIndex: Int,
            targetWeightKg: Double? = nil,
            targetReps: Int? = nil,
            targetDurationSec: Int? = nil,
            targetDistanceM: Double? = nil
        ) {
            self.id = id
            self.orderIndex = orderIndex
            self.targetWeightKg = targetWeightKg
            self.targetReps = targetReps
            self.targetDurationSec = targetDurationSec
            self.targetDistanceM = targetDistanceM
        }
    }

    @Model
    public final class PlannedExercise {
        @Attribute(.unique) public var id: UUID
        public var orderIndex: Int
        public var restSec: Int?
        public var exercise: Exercise?
        public var template: WorkoutTemplate?

        @Relationship(deleteRule: .cascade, inverse: \PlannedSet.plannedExercise)
        public var sets: [PlannedSet] = []

        /// Pass `restSec: nil` to mean "use the exercise's default rest" — not
        /// "no rest". The init normalizes nil to `exercise?.defaultRestSec ?? 90`
        /// so newly-created rows always carry a concrete value; only rows that
        /// predate the V1→V2 migration can hold nil at rest. Read rest through
        /// `resolvedRestSec` to paper over both cases.
        public init(
            id: UUID = UUID(),
            orderIndex: Int,
            exercise: Exercise? = nil,
            restSec: Int? = nil
        ) {
            self.id = id
            self.orderIndex = orderIndex
            self.restSec = restSec ?? exercise?.defaultRestSec ?? 90
            self.exercise = exercise
        }

        public var orderedSets: [PlannedSet] {
            sets.sorted { $0.orderIndex < $1.orderIndex }
        }

        public var resolvedRestSec: Int {
            restSec ?? exercise?.defaultRestSec ?? 90
        }
    }

    @Model
    public final class WorkoutTemplate {
        @Attribute(.unique) public var id: UUID
        public var name: String
        public var createdAt: Date

        @Relationship(deleteRule: .cascade, inverse: \PlannedExercise.template)
        public var plannedExercises: [PlannedExercise] = []

        public init(
            id: UUID = UUID(),
            name: String,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
        }

        public var orderedExercises: [PlannedExercise] {
            plannedExercises.sorted { $0.orderIndex < $1.orderIndex }
        }
    }

    @Model
    public final class WorkoutSession {
        @Attribute(.unique) public var id: UUID
        public var startedAt: Date
        public var endedAt: Date?
        public var template: WorkoutTemplate?
        public var templateName: String
        public var healthKitWorkoutUUID: UUID?

        @Relationship(deleteRule: .cascade, inverse: \PerformedSet.session)
        public var performedSets: [PerformedSet] = []

        public init(
            id: UUID = UUID(),
            startedAt: Date,
            templateName: String,
            template: WorkoutTemplate? = nil
        ) {
            self.id = id
            self.startedAt = startedAt
            self.templateName = templateName
            self.template = template
        }

        public var isFinished: Bool { endedAt != nil }

        public var orderedPerformedSets: [PerformedSet] {
            performedSets.sorted { $0.orderIndex < $1.orderIndex }
        }
    }

    @Model
    public final class PerformedSet {
        @Attribute(.unique) public var id: UUID
        public var orderIndex: Int
        /// The exercise's display name *at the time this set was performed*. Kept
        /// deliberately: it is not redundant with `exerciseID` — it preserves what the
        /// exercise was called then, and covers exercises later deleted from the library.
        public var exerciseName: String
        /// Lift Identity. Nil only for rows that predate V3 whose name could not be
        /// resolved against the library; the coach must tolerate that.
        public var exerciseID: UUID?
        public var exerciseIndex: Int
        public var setIndex: Int
        public var weightKg: Double?
        public var reps: Int?
        public var durationSec: Int?
        public var distanceM: Double?
        public var rpe: Int?
        public var completedAt: Date

        // The Target in effect when this set was performed.
        public var targetWeightKg: Double?
        public var targetReps: Int?
        public var targetDurationSec: Int?
        public var targetDistanceM: Double?

        // What the Coach proposed for this set, when it proposed anything.
        public var suggestedWeightKg: Double?
        public var suggestedReps: Int?
        public var suggestedDurationSec: Int?
        public var suggestedDistanceM: Double?

        public var session: WorkoutSession?

        public init(
            id: UUID = UUID(),
            orderIndex: Int,
            exerciseName: String,
            exerciseID: UUID? = nil,
            exerciseIndex: Int,
            setIndex: Int,
            weightKg: Double? = nil,
            reps: Int? = nil,
            durationSec: Int? = nil,
            distanceM: Double? = nil,
            rpe: Int? = nil,
            completedAt: Date,
            targetWeightKg: Double? = nil,
            targetReps: Int? = nil,
            targetDurationSec: Int? = nil,
            targetDistanceM: Double? = nil,
            suggestedWeightKg: Double? = nil,
            suggestedReps: Int? = nil,
            suggestedDurationSec: Int? = nil,
            suggestedDistanceM: Double? = nil
        ) {
            self.id = id
            self.orderIndex = orderIndex
            self.exerciseName = exerciseName
            self.exerciseID = exerciseID
            self.exerciseIndex = exerciseIndex
            self.setIndex = setIndex
            self.weightKg = weightKg
            self.reps = reps
            self.durationSec = durationSec
            self.distanceM = distanceM
            self.rpe = rpe
            self.completedAt = completedAt
            self.targetWeightKg = targetWeightKg
            self.targetReps = targetReps
            self.targetDurationSec = targetDurationSec
            self.targetDistanceM = targetDistanceM
            self.suggestedWeightKg = suggestedWeightKg
            self.suggestedReps = suggestedReps
            self.suggestedDurationSec = suggestedDurationSec
            self.suggestedDistanceM = suggestedDistanceM
        }
    }

    /// A Proposed Target awaiting review on the phone. Single-step moves in the usual
    /// direction never reach this table — they are applied straight to `PlannedSet` so the
    /// watch is never stale on a day the lifter skips the phone. Only proposals where the
    /// stakes justify a human land here.
    @Model
    public final class ProposedTarget {
        @Attribute(.unique) public var id: UUID
        /// The Slot this proposal is for: `PlannedExercise.id`.
        public var slotID: UUID
        /// Denormalized so a proposal survives its slot being deleted and can still be
        /// explained to the lifter.
        public var workoutName: String
        public var exerciseName: String
        public var exerciseID: UUID?
        public var proposedAt: Date
        /// `CoachOutcome` raw value — why the coach proposed this.
        public var outcomeRaw: String
        /// `ProgressionDimension` raw value — the axis that moved.
        public var dimensionRaw: String
        /// Human-readable reason, produced by the deterministic coach. Never by a model.
        public var reason: String
        /// Per-set proposed targets, ordered by the slot's set order.
        public var setsData: Data
        /// Set once the lifter accepts or dismisses; nil while pending.
        public var resolvedAt: Date?
        /// True when accepted, false when dismissed, nil while pending.
        public var wasAccepted: Bool?

        public init(
            id: UUID = UUID(),
            slotID: UUID,
            workoutName: String,
            exerciseName: String,
            exerciseID: UUID? = nil,
            proposedAt: Date,
            outcomeRaw: String,
            dimensionRaw: String,
            reason: String,
            setsData: Data,
            resolvedAt: Date? = nil,
            wasAccepted: Bool? = nil
        ) {
            self.id = id
            self.slotID = slotID
            self.workoutName = workoutName
            self.exerciseName = exerciseName
            self.exerciseID = exerciseID
            self.proposedAt = proposedAt
            self.outcomeRaw = outcomeRaw
            self.dimensionRaw = dimensionRaw
            self.reason = reason
            self.setsData = setsData
            self.resolvedAt = resolvedAt
            self.wasAccepted = wasAccepted
        }

        public var isPending: Bool { resolvedAt == nil }
    }
}

// MARK: - Module-level typealiases (current = V3)

public typealias Exercise = WorkoutSchemaV3.Exercise
public typealias PlannedSet = WorkoutSchemaV3.PlannedSet
public typealias PlannedExercise = WorkoutSchemaV3.PlannedExercise
public typealias WorkoutTemplate = WorkoutSchemaV3.WorkoutTemplate
public typealias WorkoutSession = WorkoutSchemaV3.WorkoutSession
public typealias PerformedSet = WorkoutSchemaV3.PerformedSet
public typealias ProposedTarget = WorkoutSchemaV3.ProposedTarget
