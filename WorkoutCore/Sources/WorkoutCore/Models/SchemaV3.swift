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
/// - `Exercise.progressionStep` / `loadProgressionStepKg` — the Progression Step. Two
///   fields, because a `.reps` exercise progresses on load when its slot carries a weight
///   and on reps when it does not, and a single untyped scalar would be read in whichever
///   unit the slot happened to imply. Nil means "use the default for that dimension".
/// - `CoachDecision` — the durable record of what a human decided about a proposal.
///   Proposals themselves are recomputed from history rather than stored.
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
            CoachDecision.self
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
        /// Smallest meaningful increase along the exercise's *kind-natural* axis — reps for
        /// `.reps`, duration for `.timed`, distance for `.distance` — in that axis's own
        /// unit. Nil falls back to `ProgressionDimension.defaultStep`.
        public var progressionStep: Double?

        /// Smallest meaningful increase in kilograms, used when a Slot carries a target
        /// weight and therefore progresses on load.
        ///
        /// A `.reps` exercise maps to two Progression Dimensions depending on the slot —
        /// weighted pull-ups progress on load, bodyweight pull-ups on reps — so one untyped
        /// scalar cannot serve both. Keeping the load step separate is what stops a number
        /// entered as "3 reps" being read as "3 kg".
        public var loadProgressionStepKg: Double?

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
            progressionStep: Double? = nil,
            loadProgressionStepKg: Double? = nil
        ) {
            self.id = id
            self.name = name
            self.kindRaw = kind.rawValue
            self.defaultRestSec = defaultRestSec
            self.defaultTargetReps = defaultTargetReps
            self.defaultTargetDurationSec = defaultTargetDurationSec
            self.defaultTargetDistanceM = defaultTargetDistanceM
            self.progressionStep = progressionStep
            self.loadProgressionStepKg = loadProgressionStepKg
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

        /// How many sets the Slot planned when this set was run. Recorded because it is
        /// the only way to tell "quit after one of four" from "this slot has one set" —
        /// judging a past session against today's set count reads a cut-short session as
        /// complete the moment the workout is edited.
        public var plannedSetCount: Int?

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
            plannedSetCount: Int? = nil,
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
            self.plannedSetCount = plannedSetCount
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

    /// A Proposed Target the lifter has decided on.
    ///
    /// Live proposals are **recomputed** rather than stored: the Coach is deterministic and
    /// reads only Performed Sets, so a proposal is a view of history, not a fact about the
    /// world. Storing them would create a staleness class with no good answer — a session
    /// syncs late, or a Performed Set is edited, and the stored row is wrong but still on
    /// the review screen — plus orphan lifecycle work every time a slot or workout is
    /// deleted. What must be durable is the lifter's *decision*, which is what this holds.
    ///
    /// A decision is keyed by `fingerprint` (which proposal) and `sourceSessionID` (on what
    /// evidence), so dismissing a deload means "not on the strength of that session" rather
    /// than "never again": stall again and the re-derived proposal comes back.
    @Model
    public final class CoachDecision {
        @Attribute(.unique) public var id: UUID
        /// The Slot this was for: `PlannedExercise.id`.
        public var slotID: UUID
        public var workoutID: UUID?
        public var exerciseID: UUID?
        /// Denormalized so the audit trail survives its slot being deleted.
        public var workoutName: String
        public var exerciseName: String
        /// Content identity of the proposal, from `CoachOutput.fingerprint`.
        public var fingerprint: String
        /// The session whose evidence produced the proposal.
        public var sourceSessionID: UUID?
        /// `CoachOutcome` raw value.
        public var outcomeRaw: String
        /// `ProgressionDimension` raw value.
        public var dimensionRaw: String
        public var delta: Double
        public var wasAccepted: Bool
        public var decidedAt: Date

        public init(
            id: UUID = UUID(),
            slotID: UUID,
            workoutID: UUID? = nil,
            exerciseID: UUID? = nil,
            workoutName: String,
            exerciseName: String,
            fingerprint: String,
            sourceSessionID: UUID? = nil,
            outcomeRaw: String,
            dimensionRaw: String,
            delta: Double,
            wasAccepted: Bool,
            decidedAt: Date
        ) {
            self.id = id
            self.slotID = slotID
            self.workoutID = workoutID
            self.exerciseID = exerciseID
            self.workoutName = workoutName
            self.exerciseName = exerciseName
            self.fingerprint = fingerprint
            self.sourceSessionID = sourceSessionID
            self.outcomeRaw = outcomeRaw
            self.dimensionRaw = dimensionRaw
            self.delta = delta
            self.wasAccepted = wasAccepted
            self.decidedAt = decidedAt
        }
    }
}

// MARK: - Module-level typealiases (current = V3)

public typealias Exercise = WorkoutSchemaV3.Exercise
public typealias PlannedSet = WorkoutSchemaV3.PlannedSet
public typealias PlannedExercise = WorkoutSchemaV3.PlannedExercise
public typealias WorkoutTemplate = WorkoutSchemaV3.WorkoutTemplate
public typealias WorkoutSession = WorkoutSchemaV3.WorkoutSession
public typealias PerformedSet = WorkoutSchemaV3.PerformedSet
public typealias CoachDecision = WorkoutSchemaV3.CoachDecision
