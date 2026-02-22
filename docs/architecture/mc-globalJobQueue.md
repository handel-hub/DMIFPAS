---

# DFPS 2.0 Demand Side: The Stratified Job Registry (`GlobalJobQueue`)

## 1. Architectural Overview

The `GlobalJobQueue` is the fundamental State Registry for the Demand Side of the DFPS 2.0 cluster. It holds the real-time payload and execution status of every active job buffered in Node.js memory.

Crucially, this class enforces the **Separation of State and Routing**. It is a pure data vault. It completely abandons the legacy, single-lane pagination model (which required  event-loop-blocking array loops to find pending jobs). By decoupling the storage of a job's payload from the pipeline that routes it, this registry can ingest and update thousands of jobs per second while giving the Job Scoring Engine instant  access to the exact slice of data it needs.

---

## 2. Engineering Decisions & The "Why"

### A. The  State Vault (The Map)

* **Implementation:** `this.globalJobQueue = new Map()`
* **The Rationale:** In a naive queue, finding a job to update its status (e.g., from `PENDING` to `COMPLETED`) requires searching through a massive array. As the queue grows, this  search chokes the V8 event loop. By using a JavaScript `Map`, every single status update, data mutation, and deletion executes in strict  time.

### B. The Stratified Priority Buckets

* **Implementation:** Replacing a single execution array with isolated priority arrays (e.g., Critical, High, Normal, Low) that store *only* the Job ID.
* **The Rationale:** Storing entire job objects in a single array causes FIFO bias, where a flood of new high-priority jobs mathematically starves older low-priority jobs forever.
* **The Optimization:** By physically isolating the Job IDs into separate tiers, the Scheduler can easily extract a proportional slice of IDs from every bucket. Because the database already queries them chronologically, pushing IDs to the back of these arrays perfectly maintains FIFO ordering with zero Node.js sorting required.

### C. The Write-Behind Cache (Database IOPS Protection)

* **Implementation:** `this.writeDbQueue = new Map()` alongside asynchronous `write()` boundaries.
* **The Rationale:** Executing a synchronous PostgreSQL `UPDATE` every time a single file changes status would saturate the database connection pool and block the hot path.
* **The Optimization:** The registry stages these updates in the `writeDbQueue` memory buffer. A scheduled background function can later process this Map as a single batch operation, drastically reducing Database IOPS and completely insulating the routing engine from disk latency.

---

## 3. Class Initialization & Persistence Dependencies

When instantiating the `GlobalJobQueue`, the system relies on injected persistence boundaries to ensure the class remains strictly database-agnostic and unit-testable.

* **`writeFunction`:** An injected asynchronous dependency used by the `write()` method to batch-upsert the current `writeDbQueue` state back to the database.
* **`fetchFunction` (Method Level):** An injected dependency passed to the `fetch()` method to hydrate the queue from cold storage during pipeline refills.
* **`jobScheduleQueue`:** The dedicated array used to build and return the exact quota of jobs requested by the Scoring Engine.
* **`structureChange` / `deleteWriteJobs`:** Boolean flags used to safely orchestrate asynchronous cache-flushing and garbage collection.

---

## 4. Stratified Extraction & "Ghost IDs"

The extraction pipeline (`scheduleQueue`) completely avoids using expensive array manipulation like `Array.splice()`.

*If a user cancels a job, or a Local Coordinator completes it, the job's status updates in the Map, but its ID is left inside the routing array. When the extraction engine pulls that ID, it checks the Map. If the job is no longer `PENDING`, the engine treats it as a "Ghost ID", immediately discards it, and grabs the next ID in  time without ever re-indexing an array.*

---

## 5. The Job Update Payload (Data Contract)

The `update(id, updateData)` method dynamically merges incoming state changes from the Local Coordinators into the warm `Map` and simultaneously stages them in the `writeDbQueue`.

Example payload to update a job's progress:

```json
{
  "status": "PROCESSING",
  "progress": 45,
  "assigned_node": "coordinator-7A",
  "updated_at": 1708556400000
}

```

---

## 6. State Hydration & Flush Lifecycle

* **Hydration (`fetch`):** Orchestrates the injected `fetchFunction` to pull a stratified batch of jobs from PostgreSQL, injecting their payloads into the `globalJobQueue` Map and their IDs into the priority pipes.
* **Extraction (`scheduleQueue`):** Slices a proportional quota of IDs from the priority pipes, retrieves the full job objects from the Map, filters out Ghost IDs, and hands the clean array to the Scoring Engine.
* **Mutation (`update`):** Applies  state updates to the main Map and stages the exact diff inside the `writeDbQueue`.
* **Flushing (`write` & `deleteJobs`):** Scheduled background processes that invoke the `writeFunction` to flush staged updates, verify the write acknowledgment, and safely garbage-collect completed jobs from memory.

---