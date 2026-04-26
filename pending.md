job_id
calculatedScore          ← already computed by AdaptiveJobScoringEngine
priority                 ← raw value, for the LC's reference
stages[]                 ← ordered list defining the DAG
  stage.id
  stage.plugin_id        ← which plugin executes this stage
  stage.depends_on[]     ← stage IDs this stage waits for
  stage.size_bytes       ← input payload size (drives RAM and duration estimates)
  stage.supports_streaming
  stage.estimated_ram_mb ← from MC scoring engine, used as COSTING seed
  stage.cpu_millicores   ← MC's cluster-wide estimate
  stage.estimated_duration_ms ← MC's cluster-wide estimate
cluster_profile          ← MC's learned profiles per plugin_id as cold-start seed
  { plugin_id → { spawn_latency_ms, cpu_millicores, duration_per_mb_ms, base_overhead_mb } }

  CONTRACT SENT BY MC

  