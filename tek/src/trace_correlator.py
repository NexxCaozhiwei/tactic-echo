from dataclasses import dataclass


@dataclass(frozen=True)
class CorrelationResult:
    matched: bool
    reason: str
    sequence: int | None = None
    action_id: str | None = None


def correlate(te_signal: dict, tek_trace: dict) -> CorrelationResult:
    for key in ("protocolVersion", "sessionEpoch", "catalogFingerprint"):
        te_value = te_signal.get(key)
        tek_value = _trace_value(tek_trace, key)
        if te_value != tek_value:
            return CorrelationResult(False, f"{key}_mismatch:{te_value}:{tek_value}")

    te_sequence = te_signal.get("sequence")
    tek_sequence = tek_trace.get("sequence")
    if te_sequence != tek_sequence:
        return CorrelationResult(False, f"sequence_mismatch:{te_sequence}:{tek_sequence}")

    te_action_code = te_signal.get("actionCode")
    tek_action_code = tek_trace.get("action_code")
    if te_action_code != tek_action_code:
        return CorrelationResult(False, f"action_code_mismatch:{te_action_code}:{tek_action_code}", te_sequence)

    te_action_id = te_signal.get("actionId")
    tek_action_id = tek_trace.get("action_id")
    if te_action_id != tek_action_id:
        return CorrelationResult(False, f"action_id_mismatch:{te_action_id}:{tek_action_id}", te_sequence)

    return CorrelationResult(True, "matched", te_sequence, te_action_id)


def _trace_value(trace: dict, camel_key: str):
    snake = []
    for char in camel_key:
        if char.isupper():
            snake.append("_")
            snake.append(char.lower())
        else:
            snake.append(char)
    return trace.get("".join(snake))
