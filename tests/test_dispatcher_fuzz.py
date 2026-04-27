# tests/test_dispatcher_fuzz.py
import random
import pytest
from typing import List, Dict
from ee import Task, OriginalDispatcher, OptimizedDispatcher, Reservoir

def generate_deep_dag(num_nodes: int, depth: int, max_branch: int = 3) -> List[Task]:
    layers = depth
    nodes_per_layer = max(1, num_nodes // layers)
    tasks = []
    id_counter = 0
    layer_nodes = []
    for layer in range(layers):
        count = nodes_per_layer if layer < layers - 1 else (num_nodes - id_counter)
        if count <= 0:
            count = 1
        this_layer = []
        for _ in range(count):
            tid = f"T{id_counter}"
            program_id = f"P{random.randint(0, max(1, layers//3))}"
            t = Task(
                id=tid, job_id="Jfuzz", program_id=program_id,
                duration_ms=random.randint(50, 500),
                cpu=random.choice([100,200,500]),
                ram=random.choice([100,500,1000]),
                spawn_latency_ms=random.randint(50, 1200),
                job_score=random.uniform(10,200),
                pos_weight=random.uniform(0.5,1.5),
                depends_on=[], children=[]
            )
            tasks.append(t)
            this_layer.append(tid)
            id_counter += 1
        layer_nodes.append(this_layer)

    for i in range(len(layer_nodes)-1):
        for src in layer_nodes[i]:
            targets = random.sample(layer_nodes[i+1], k=min(max_branch, len(layer_nodes[i+1])))
            for tgt in targets:
                s = next(t for t in tasks if t.id == src)
                d = next(t for t in tasks if t.id == tgt)
                s.children.append(d.id)
                d.depends_on.append(s.id)
    return tasks

@pytest.mark.parametrize("depth", [15, 20, 25, 30, 35])
def test_fuzz_deep_dag(depth):
    num_nodes = max(200, depth * 10)
    tasks = generate_deep_dag(num_nodes=num_nodes, depth=depth, max_branch=3)
    node_spec = {"total_cpu": 16000, "total_ram": 64000, "num_slots": 16, "warm_start_threshold": 0.90}
    orig = OriginalDispatcher(**node_spec)
    opt = OptimizedDispatcher(**node_spec)

    mo = orig.build_schedule([t for t in tasks])
    mp = opt.build_schedule([t for t in tasks])

    assert len(mo) == len(tasks)
    assert len(mp) == len(tasks)

    tasks_by_id = {t.id: t for t in tasks}
    def validate(manifest):
        cap_cpu = int(node_spec["total_cpu"] * Reservoir.SAFETY_FACTOR)
        cap_ram = int(node_spec["total_ram"] * Reservoir.SAFETY_FACTOR)
        events = []
        for e in manifest:
            events.append((e.start_time, 1, e))
            events.append((e.end_time, -1, e))
        events.sort(key=lambda x: (x[0], -x[1]))
        cur_cpu = 0
        cur_ram = 0
        for time_ms, typ, entry in events:
            t = tasks_by_id[entry.task_id]
            if typ == 1:
                cur_cpu += t.cpu
                cur_ram += t.ram
                assert cur_cpu <= cap_cpu
                assert cur_ram <= cap_ram
            else:
                cur_cpu -= t.cpu
                cur_ram -= t.ram
    validate(mo)
    validate(mp)

    assert set(e.task_id for e in mo) == set(e.task_id for e in mp)
