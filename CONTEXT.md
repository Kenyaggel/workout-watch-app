# Workout Training

The language of this project: authoring workouts, running them set by set on the wrist, and
progressing their targets over time.

Three different things in this domain are all loosely called "exercise," and three different
things are all loosely called "workout." The entries below pick one word for each and name the
ones to stop using.

## The plan

**Workout**:
A reusable plan for one training session — an ordered list of slots.
_Avoid_: Template, Routine, Program, Split

**Exercise**:
A movement in the reusable library, defined independently of any workout that uses it.
_Avoid_: Lift, Movement, Activity

**Slot**:
One exercise's place in one workout, carrying that workout's rest and sets for it. The same
exercise appearing in two workouts is two slots.
_Avoid_: Planned exercise, workout exercise, entry

**Target**:
The intended weight, reps, duration, or distance for a single set.
_Avoid_: Goal, prescription, plan

## Performing

**Session**:
One actual performance of a workout, from start to finish.
_Avoid_: Workout (when you mean the performance), run, instance, activity

**Performed Set**:
A set actually completed during a session, recording what was really lifted rather than what
was intended.
_Avoid_: Completed set, actual, result, log entry

**Phase**:
Which of the three states a session is in: in-set, rest, or prep.
_Avoid_: Mode, state, step, stage

**RPE**:
Rate of perceived exertion for a completed set, 1–10. Always optional — its absence means "not
recorded", never "easy".
_Avoid_: Effort, difficulty, intensity

## Progression

**Coach**:
The deterministic rules that turn session history into proposed targets. The coach is the only
source of a number; a language model never is.
_Avoid_: AI, the model, the algorithm

**Lift Identity**:
What makes two performed sets count as the same exercise across time. It is the exercise's
stable identity, never its display name.
_Avoid_: Exercise name, name matching

**Progression Dimension**:
The single axis along which an exercise gets harder — load, reps, duration, or distance. Every
exercise has exactly one.
_Avoid_: Progression type, axis, metric, unit

**Progression Step**:
The smallest meaningful increase along an exercise's progression dimension, expressed in that
dimension's own unit.
_Avoid_: Increment, delta, jump, bump

**Proposed Target**:
A target the coach suggests for a future session, before a human has accepted it.
_Avoid_: Suggestion, recommendation, prediction, guess

**Stall**:
A session in which a slot's targets were not met.
_Avoid_: Fail, miss, plateau

**Deload**:
A deliberate reduction of a slot's targets after repeated stalls.
_Avoid_: Backoff, reset, regression, drop

**Narration**:
Plain-language explanation of what the coach proposed and why. Never the source of a number.
_Avoid_: Insights, AI advice, analysis
