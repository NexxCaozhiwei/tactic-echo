"""Small local sampler benchmark used for P4-C verification on Windows."""
from __future__ import annotations

import json
import statistics
import time
from dataclasses import asdict, dataclass
from typing import Callable

from tek.src.screen_sampler import SignalLayout


@dataclass(frozen=True)
class SamplerBenchmarkResult:
    backend: str
    iterations: int
    warmup_iterations: int
    total_ms: float
    average_ms: float
    p50_ms: float
    p95_ms: float
    samples_per_second: float

    def to_dict(self) -> dict:
        return asdict(self)


def benchmark_sampler(
    sampler,
    layout: SignalLayout = SignalLayout(),
    *,
    iterations: int = 100,
    warmup_iterations: int = 5,
    clock: Callable[[], float] = time.perf_counter,
) -> SamplerBenchmarkResult:
    """Measure one local strip sampler; this never creates TEK input."""
    iterations = max(1, int(iterations))
    warmup_iterations = max(0, int(warmup_iterations))
    for _ in range(warmup_iterations):
        sampler.sample(layout)
    durations: list[float] = []
    for _ in range(iterations):
        started = clock()
        sampler.sample(layout)
        durations.append(max(0.0, (clock() - started) * 1000.0))
    ordered = sorted(durations)
    total = sum(durations)
    average = total / len(durations)
    index95 = min(len(ordered) - 1, max(0, int(round((len(ordered) - 1) * 0.95))))
    return SamplerBenchmarkResult(
        backend=str(getattr(sampler, "backend", "unknown")),
        iterations=iterations,
        warmup_iterations=warmup_iterations,
        total_ms=round(total, 4),
        average_ms=round(average, 4),
        p50_ms=round(statistics.median(ordered), 4),
        p95_ms=round(ordered[index95], 4),
        samples_per_second=round(1000.0 / average, 2) if average > 0 else 0.0,
    )


def main(argv=None) -> int:
    import argparse
    from tek.src.screen_sampler import runtime_pixel_sampler

    parser = argparse.ArgumentParser(description="Benchmark one TEAP strip sampler; no input is sent.")
    parser.add_argument("--backend", choices=("auto", "pillow", "gdi", "gdi_blt"), default="auto")
    parser.add_argument("--iterations", type=int, default=200)
    parser.add_argument("--x", type=int, default=12)
    parser.add_argument("--y", type=int, default=12)
    parser.add_argument("--block-size", type=int, default=10)
    parser.add_argument("--block-gap", type=int, default=2)
    args = parser.parse_args(argv)
    sampler = runtime_pixel_sampler("pillow" if args.backend == "auto" else args.backend)
    result = benchmark_sampler(
        sampler,
        SignalLayout(x=args.x, y=args.y, block_size=args.block_size, block_gap=args.block_gap),
        iterations=args.iterations,
    )
    print(json.dumps(result.to_dict(), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
