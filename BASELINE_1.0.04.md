# Tactic Echo 1.0.04 Baseline

This source baseline fixes the AutoBurst Phase 1 internal-hold self-latch observed in the 2026-07-02 live diagnostic.

- Internal AutoBurst waits are encoded as authenticated `armed + observationOnly + dispatchOrigin=burst` frames, not as `paused`.
- TEK observes those frames without input and without BindingToken validation.
- AutoBurst remains eligible to advance once GCDGate reaches `QUEUE_WINDOW` or its step confirmation resolves.
- The user-facing Start/Pause state is no longer masked by an old window-departure lock.
- Focused mode declines takeover when prerequisites are unavailable instead of suppressing the official recommendation.

Historical baselines remain available for traceability only.
