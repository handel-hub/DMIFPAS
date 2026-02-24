
---

# DFPS 2.0 Job Scoring Engine: Technical Specification (v2.1 - Hardened)

## 1. Engine Overview

The `JobScoringEngine` acts as the dedicated mathematical brain (Demand Shaper) of the Main Coordinator. It is entirely decoupled from the database and operates strictly in-memory. Its sole responsibility is to ingest a stratified batch of raw `PENDING` jobs, apply a heavily bounded and statistically smoothed Time-Yield adaptive formula, and output a mathematically ranked array for the Scheduler to dispatch.

---

## 2. The Adaptive Weight Metric (W_k)

Before scoring individual jobs, the engine calculates a holistic, self-tuning health weight for every Job Type. This process uses statistical blending to protect the system from cold-start volatility, runaway amplification, and permanent quarantine deadlocks.

### 2.1 The Circuit Breaker (Bayesian Yield)

To prevent the "Fast Failure Trap" and avoid a 0% yield permanently locking out a job type, the engine uses Bayesian (Laplace) Smoothing. By adding a smoothing constant (`Epsilon`, e.g., 2), the system mathematically pretends it has already seen 2 successes and 2 failures.

`Yield_k = (SuccessCount + Epsilon) / (SuccessCount + FailCount + (2 * Epsilon))`

*(A completely failing plugin with 0 successes and 1 failure yields 0.4, preventing an inescapable mathematical zero).*

### 2.2 The Raw Measured Weight

The engine calculates the physical performance ratio for the current Exponential Moving Average (EMA) window. The `MAX(1, ...)` clamp prevents Infinity division errors if a glitch reports a 0ms execution.

`W_raw = (ExpectedTime_k / MAX(1, ActualTimeEMA_k)) * Yield_k`

### 2.3 Credibility Blending (The Cold Start Fix)

To prevent high-variance jitter when sample sizes are small (e.g., a single failure skewing the weight by 25%), the engine applies a Confidence Factor (`C`) to blend the raw measurement against a neutral baseline (1.0). `N_min` is the statistical confidence threshold (e.g., 50).

`C = MIN(1.0, TotalSamples / N_min)`
`W_blended = (C * W_raw) + ((1 - C) * 1.0)`

*(If `TotalSamples` is 2, the engine only trusts 4% of `W_raw` and relies 96% on the neutral baseline).*

### 2.4 The Bounded Final Weight

Finally, the blended weight is strictly clamped to prevent both resource starvation (underutilization spiral) and explosive workload skew.

`W_k = MAX(W_min, MIN(W_max, W_blended))`

* **`W_min` (e.g., 0.1):** Guarantees even critically failing job types maintain a microscopic priority presence, allowing the system to detect recovery automatically.
* **`W_max` (e.g., 1.5):** Prevents artificially fast jobs from gaining an explosive multiplier and starving the cluster.

---

## 3. The Global Job Score Formula

The engine calculates the exact priority value of a job using a structurally bounded Base-and-Multiplier approach.

`Score_job = BasePriority * MIN(MaxAging, 1.0 + (Uptime_j / T_aging)) * (W_k / SQRT(MAX(0.1, Size_j)))`

**Parameter Breakdown:**

* **BasePriority:** The static business value tier (`CRITICAL` = 100, `NORMAL` = 2, `LOW` = 1).
* **Capped Aging Multiplier:** `MIN(MaxAging, ...)` prevents unbounded score inflation. A `MaxAging` of 3.0 allows a `LOW` job to triple its score over time, preventing starvation without mathematically inverting the business hierarchy.
* **Adaptive Health (`W_k`):** The statistically smoothed and bounded metric calculated in Section 2.
* **Sublinear Size Penalty:** `SQRT(MAX(0.1, Size_j))` dampens the penalty curve. Using a square root (`SQRT`) prevents the aggressive priority swings of a linear inverse, ensuring massive but highly important files are not indefinitely starved.

---

## 4. The Execution Pipeline (The Hot Path)

To prevent Implicit FIFO Bias from overriding the scoring math, the pipeline utilizes proportional extraction.

1. **Stratified Sampling:** Triggered by the Scheduler, the engine requests a mixed demographic of N jobs from the Registry's pending pipe (e.g., 20 Critical, 15 High, 10 Normal, 5 Low) rather than a strict chronological FIFO slice.
2. **The Compute:** The engine loops over these exact N jobs in RAM, applying the bounded `Score_job` formula. (Compute time: < 1ms).
3. **The Sort:** The engine sorts the scored jobs in descending order based on their newly calculated `Score_job`.
4. **The Handoff:** The sorted array of winners is returned directly to the Scheduler's hot dispatch buffer.

---

## 5. Mathematical Stress Testing & Edge Cases

| Threat / Edge Case | Mathematical Defense | Execution & System Result |
| --- | --- | --- |
| **Early Sample Bias (Cold Start)** | **Credibility Blending** (`C`) | A single network timeout on a new deployment is ignored. At N=2, the engine relies 96% on the baseline (1.0), keeping the queue stable until true metrics establish. |
| **Fast Failure Trap** | **Bayesian Yield** + **`W_min` Floor** | A plugin crashing instantly drops in priority but never hits 0.0. The 0.1 floor ensures a trickle of test jobs route to the plugin, auto-detecting when a fix is deployed. |
| **The "Heavy Wall" vs. VIP** | **Multiplicative Base** + **`SQRT(Size)`** | A massive backlog of old, huge `NORMAL` jobs cannot wash out a tiny, new `CRITICAL` job. The sublinear size modifier rewards the VIP without permanently burying the massive files. |
| **The Starving Peasant** | **Max Aging Clamp** (`MaxAging`) | Unbounded aging cannot cause cyclical demand waves. `LOW` jobs overtake fresh `NORMAL` jobs over time, but are mathematically walled off from breaking the `CRITICAL` ceiling. |

---

