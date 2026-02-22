
---

# 🤝 DFPS 2.0: The Contextual Affinity Matcher

## 1. Architectural Overview

The `AffinityMatcher` acts as the final decision boundary inside the DFPS 2.0 Main Coordinator. While the Demand Side ranks jobs by urgency and the Supply Side filters nodes by physical capacity, the Affinity Matcher answers a highly specific historical question:

> *"Given a specific Job  and a capacity-safe Candidate Node , how suitable is this exact node for this exact file type and size?"*

To answer this without relying on heavy machine learning libraries, the Matcher operates as a highly optimized, strictly  **Contextual Multi-Armed Bandit (MAB)**.

**Core Philosophy:** Affinity is *advisory*. Capacity is *protective*. The Matcher only evaluates nodes that have already passed the hard hardware constraints of the Supply Side.

---

## 2. The 3D State Matrix (Data Model)

Instead of evaluating nodes as monolithic machines, the Matcher breaks their historical performance down into a hyper-specific 3D statistical matrix: `AffinityStats[FileType][Node][SizeBucket]`.

**Size Buckets:**
Files of the same type (e.g., `.mp4`) scale non-linearly. To prevent dimensional distortion, jobs are routed into fixed historical buckets:

* **SMALL:** `< 10MB`
* **MEDIUM:** `10MB - 500MB`
* **LARGE:** `> 500MB`

For every unique combination, the system maintains a lightweight, 6-field "Stats Pocket" in memory:

* `count` (Sample size)
* `ema_time_per_mb` (Speed)
* `variance` (Stability)
* `success_rate` (Reliability)
* `last_updated` (Timestamp)

*With 50 file types, 20 Local Coordinators, and 3 buckets, the system holds just 3,000 pockets. The memory footprint is negligible.*

---

## 3. The Mathematical Pipeline

When a Local Coordinator completes a job, the Main Coordinator updates the corresponding Stats Pocket in strictly  time using four mathematical mechanisms:

### A. Dimensional Normalization (Time per MB)

To compare a 5MB text file against a 9MB text file fairly, the system normalizes execution speed.
`Time_per_MB = ExecutionTime / MAX(FileSize_MB, 0.1)`
*Note: The 0.1 clamp prevents divide-by-zero errors for microscopic files.*

### B. Variance Stabilization (Welford’s Algorithm)

Relying purely on average speed is dangerous; a node that averages 5 seconds but wildly swings between 1s and 9s is structurally unstable. The system uses **Welford’s Online Algorithm** to maintain a running variance without keeping historical arrays in memory.
`VariancePenalty = Lambda * SQRT(Variance)`
*(Lambda  ensures temporary spikes do not permanently destroy a node's score).*

### C. Bayesian Success Rate

To prevent a single failure on a new node from dropping its success rate to an unrecoverable 0%, the system uses a smoothing constant (`s = 3`).
`AdjustedSuccessRate = (Successes + s) / (Total + 2s)`

### D. The Asymptotic Confidence Curve

Standard schedulers use "hard cliffs" (e.g., trust a node only after 30 jobs). This model uses a smooth exponential decay function to grow confidence organically as the sample size (`n`) increases.
`Confidence = 1 - EXP(-n / k)`
*If : at , confidence is . At , confidence is . At , confidence is .*

---

## 4. The Final Scoring Fusion

When evaluating a node for a pending job, the Matcher calculates a continuous `FinalAffinity` score using multiplicative fusion. This mathematically ties the node's raw speed directly to its reliability.

1. **Calculate the Performance Base:**
`PerfComponent = 1 / (EMA_Time_per_MB + VariancePenalty)`
2. **Apply the Reliability Multiplier:**
`RawScore = PerfComponent * AdjustedSuccessRate`
3. **Apply the Confidence Scaling:**
`FinalAffinity = Confidence * RawScore`

**Behavioral Result:** If a node processes data at lightning speed but fails 50% of the time, its `RawScore` is physically halved. Throughput cannot outrun unreliability. If the node has no historical data for this file type, it receives a baseline constant fallback score.

---

## 5. The Epsilon-Greedy Explorer

Historical routing models suffer from "Stale Data Starvation." If Node A was terrible at rendering video three months ago, its historical score will be terrible forever, even if a developer just upgraded its GPU.

To continuously probe for system upgrades, the Matcher implements an **Exploration Mechanism** governed by a global Epsilon ().

* **Exploitation (95%):** The Matcher sorts the capacity-safe nodes by `FinalAffinity` and picks the best one.
* **Exploration (5%):** The Matcher entirely ignores the Affinity math and picks a random node from the capacity-safe pool.

This global exploration randomly injects new sample data into stale pockets, allowing the `EMA_Time_per_MB` to gradually "heal" if a node's physical performance improves over time.

---

## 6. Operational Synthesis

The DFPS 2.0 Affinity Matcher is an advisory engine that completely solves dimensional distortion (via size normalization), corrects metric skew (via bucket segmentation), and degrades safely under adversarial loads.

Because every mathematical update and retrieval executes in  time using simple arithmetic, the Node.js event loop can process thousands of complex contextual matches per second without ever dropping a tick.

