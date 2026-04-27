#!/usr/bin/env python3
import os
import sys

# Ensure repository root is on sys.path so local modules (ee.py) can be imported.
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

import json
import random
import time
# ... rest of file ...
from ee import Task, OptimizedDispatcher

def generate_deterministic_workload(n=100, seed=42):
    random.seed(seed)
    tasks: List[Task] = []
    for i in range(n):
        t = Task(
            id=f"T{i}",
            job_id=f"J{i//10}",
            program_id=f"P{i%5}",
            duration_ms=200 + (i % 7) * 10,
            cpu=100 if i%3==0 else 200,
            ram=200 if i%4==0 else 500,
            spawn_latency_ms=300 + (i%5)*50,
            job_score=100.0,
            pos_weight=1.0,
            depends_on=[],
            children=[]
        )
        tasks.append(t)
    return tasks

def run_once():
    node_spec = {"total_cpu": 16000, "total_ram": 64000, "num_slots": 16, "warm_start_threshold": 0.90}
    disp = OptimizedDispatcher(**node_spec)
    tasks = generate_deterministic_workload(100, seed=123)
    t0 = time.perf_counter()
    manifest = disp.build_schedule(tasks)
    t1 = time.perf_counter()
    return t1 - t0

def main():
    runs = []
    for _ in range(3):
        runs.append(run_once())
    median_time = sorted(runs)[1]
    out = {"median_time_s": median_time, "runs": runs}
    print(json.dumps(out))

if __name__ == "__main__":
    main()
