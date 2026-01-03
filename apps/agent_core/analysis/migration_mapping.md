# Migration Mapping Document

## Overview

This document provides a detailed mapping of how modules, database operations, and behaviors will be migrated from the current structure to the new layered architecture.

## Module Migration Mapping

### 1. Agent Core → Agent Core (Domain Layer)

**Modules to Keep (Clean of Infrastructure)**:
```
AgentCore.Llm.LLMProfile                    → AgentCore.Profiles.LLMProfile
AgentCore.Llm.Provider                      → AgentCore.Providers.Provider  
AgentCore.Llm.RunSnapshot                   → AgentCore.Runs.RunSnapshot
AgentCore.Llm.RunView                       → AgentCore.Runs.RunView
AgentCore.Llm.Runs                          → AgentCore.Runs (API)
AgentCore.Llm.GenerationParams             → AgentCore.Profiles.GenerationParams
AgentCore.Llm.Budgets                      → AgentCore.Profiles.Budgets
AgentCore.Llm.ModelRef                     → AgentCore.Providers.ModelRef
AgentCore.Llm.ProviderContract             → AgentCore.Providers.Behavior
AgentCore.Llm.ProviderRequest              → AgentCore.Providers.Request
AgentCore.Llm.ProviderResponse             → AgentCore.Providers.Response
AgentCore.Llm.ProviderAdapter              → AgentCore.Providers.Adapter
AgentCore.Llm.ProviderRouter               → AgentCore.Providers.Router
AgentCore.Llm.Validator                    → AgentCore.Validation.Validator
AgentCore.Llm.Resolver                     → AgentCore.Profiles.Resolver
AgentCore.Llm.Overrides                    → AgentCore.Profiles.Overrides
AgentCore.Llm.InvocationConfig             → AgentCore.Profiles.InvocationConfig

AgentCore.WorkflowEngine.Spec              → AgentCore.Workflows.Spec
AgentCore.WorkflowEngine.Context           → AgentCore.Workflows.Context  
AgentCore.WorkflowEngine.Step              → AgentCore.Workflows.Step
AgentCore.WorkflowEngine.WorkflowResult    → AgentCore.Workflows.WorkflowResult
```

**Store Behaviors to Keep (Interface Only)**:
```
AgentCore.Llm.RunStore                     → AgentCore.Stores.RunStore
AgentCore.Llm.ProfileStore                 → AgentCore.Stores.ProfileStore
AgentCore.Llm.PlanStore                    → AgentCore.Stores.PlanStore
```

**New Behaviors to Create**:
```
                                           → AgentCore.Stores.MemoryStore
                                           → AgentCore.Stores.ConversationStore
                                           → AgentCore.Workflows.Engine (behavior)
                                           → AgentCore.Tools.Behavior
```

**Modules to Remove (Infrastructure)**:
```
AgentCore.Llm.RunStore.Ecto               → DELETE (move logic to agent_infra)
AgentCore.Llm.ProfileStore.Ecto           → DELETE (move logic to agent_infra)
```

### 2. Agent Core → Agent Runtime (Runtime Layer)

**Modules to Move**:
```
AgentCore.WorkflowEngine.Runtime           → AgentRuntime.Workflows.Engine
AgentCore.WorkflowEngine.Agent             → AgentRuntime.Agent
AgentCore.WorkflowEngine.Registry          → AgentRuntime.Workflows.Registry
AgentCore.WorkflowEngine.Compiler          → AgentRuntime.Workflows.Compiler
AgentCore.WorkflowEngine.LlmIntegration    → AgentRuntime.Workflows.LlmIntegration
```

**New Modules to Create**:
```
                                           → AgentRuntime.Stores.RunStoreWrapper
                                           → AgentRuntime.Stores.ProfileStoreWrapper
                                           → AgentRuntime.Stores.PlanStoreWrapper
                                           → AgentRuntime.Stores.MemoryStoreWrapper
                                           → AgentRuntime.Tools.Executor
                                           → AgentRuntime.Tools.Registry
                                           → AgentRuntime.Providers.HTTPClient
                                           → AgentRuntime.Providers.Router
```

### 3. Agent Web → Agent Infra (Infrastructure Layer)

**Database Modules to Move**:
```
AgentWeb.Repo                              → AgentInfra.Repo
AgentWeb.Schemas.RunRecord                 → AgentInfra.Schema.Run
AgentWeb.Schemas.ProfileRecord             → AgentInfra.Schema.Profile
AgentWeb.Memory.MemoryChunk                → AgentInfra.Schema.MemoryChunk
AgentWeb.Memory.Chunk                      → AgentInfra.Schema.Chunk
AgentWeb.Llm.RunStoreEcto                  → AgentInfra.StoreEcto.RunStore
```

**Migrations to Move**:
```
apps/agent_web/priv/repo/migrations/*     → apps/agent_infra/priv/repo/migrations/*
apps/agent_web/priv/repo/seeds.exs        → apps/agent_infra/priv/repo/seeds.exs
```

**New Store Implementations to Create**:
```
                                           → AgentInfra.StoreEcto.ProfileStore
                                           → AgentInfra.StoreEcto.PlanStore
                                           → AgentInfra.StoreEcto.MemoryStore
                                           → AgentInfra.StoreEcto.ConversationStore
```

### 4. Agent Core → Test Assessment App

**Complete Domain Migration**:
```
AgentCore.TestAssessment.*                 → TestAssessmentApp.*
Mix.Tasks.TestAssessment                   → TestAssessmentApp.Mix.Tasks.Assessment
```

**Specific Module Mappings**:
```
AgentCore.TestAssessment.AssessmentReport  → TestAssessmentApp.AssessmentReport
AgentCore.TestAssessment.Categorization    → TestAssessmentApp.Categorization
AgentCore.TestAssessment.CLI               → TestAssessmentApp.CLI
AgentCore.TestAssessment.ConfigValidator   → TestAssessmentApp.ConfigValidator
AgentCore.TestAssessment.CoverageAnalysis  → TestAssessmentApp.CoverageAnalysis
AgentCore.TestAssessment.FileDiscovery     → TestAssessmentApp.FileDiscovery
AgentCore.TestAssessment.RecommendationEngine → TestAssessmentApp.RecommendationEngine
AgentCore.TestAssessment.TestParser        → TestAssessmentApp.TestParser
AgentCore.TestAssessment.TestSuiteOptimizer → TestAssessmentApp.TestSuiteOptimizer
... (all 25+ modules)
```

## Behavior Interface Mapping

### Current Behavior Interfaces (Agent Core)

**1. RunStore Behavior**:
```elixir
@callback put(RunSnapshot.t()) :: {:ok, run_id()} | {:error, error()}
@callback get(run_id()) :: {:ok, RunView.t()} | {:error, :not_found}
@callback list(keyword()) :: {:ok, [RunView.t()]} | {:error, error()}
@callback mark_started(run_id()) :: {:ok, run_id()} | {:error, :not_found} | {:error, error()}
@callback mark_finished(run_id(), outcome()) :: {:ok, run_id()} | {:error, :not_found} | {:error, error()}
@callback mark_failed(run_id(), error(), outcome()) :: {:ok, run_id()} | {:error, :not_found} | {:error, error()}
```

**2. ProfileStore Behavior**:
```elixir
@callback put(LLMProfile.t()) :: {:ok, String.t()} | {:error, term()}
@callback get(id()) :: {:ok, LLMProfile.t()} | :error
@callback list(opts()) :: [LLMProfile.t()]
```

**3. PlanStore Behavior**:
```elixir
@callback get(plan_id(), version()) :: {:ok, Definition.t()} | {:error, :not_found} | {:error, term()}
@callback get_latest(plan_id()) :: {:ok, Definition.t()} | {:error, :not_found} | {:error, term()}
@callback put(Definition.t()) :: {:ok, Definition.t()} | {:error, term()}
@callback list(keyword()) :: {:ok, [Definition.t()]} | {:error, term()}
```

### New Behavior Interfaces Needed

**4. MemoryStore Behavior**:
```elixir
defmodule AgentCore.Stores.MemoryStore do
  @callback store_chunk(conversation_id :: String.t(), chunk :: map()) :: {:ok, String.t()} | {:error, term()}
  @callback get_chunk(chunk_id :: String.t()) :: {:ok, map()} | {:error, :not_found}
  @callback search_chunks(conversation_id :: String.t(), query :: String.t(), opts :: keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback delete_chunk(chunk_id :: String.t()) :: :ok | {:error, term()}
  @callback list_chunks(conversation_id :: String.t(), opts :: keyword()) :: {:ok, [map()]} | {:error, term()}
end
```

**5. ConversationStore Behavior**:
```elixir
defmodule AgentCore.Stores.ConversationStore do
  @callback create_conversation(attrs :: map()) :: {:ok, map()} | {:error, term()}
  @callback get_conversation(conversation_id :: String.t()) :: {:ok, map()} | {:error, :not_found}
  @callback update_conversation(conversation_id :: String.t(), attrs :: map()) :: {:ok, map()} | {:error, term()}
  @callback delete_conversation(conversation_id :: String.t()) :: :ok | {:error, term()}
  @callback list_conversations(opts :: keyword()) :: {:ok, [map()]} | {:error, term()}
end
```

**6. Workflow Engine Behavior**:
```elixir
defmodule AgentCore.Workflows.Engine do
  @callback execute(spec :: AgentCore.Workflows.Spec.t(), input :: map()) :: {:ok, map()} | {:error, term()}
  @callback validate_spec(spec :: AgentCore.Workflows.Spec.t()) :: :ok | {:error, [atom()]}
end
```

**7. Tools Behavior**:
```elixir
defmodule AgentCore.Tools.Behavior do
  @callback execute(input :: map()) :: {:ok, map()} | {:error, term()}
  @callback schema() :: map()
  @callback name() :: String.t()
  @callback description() :: String.t()
end
```

**8. Provider Behavior** (Update existing):
```elixir
defmodule AgentCore.Providers.Behavior do
  @callback execute(request :: AgentCore.Providers.Request.t()) :: {:ok, AgentCore.Providers.Response.t()} | {:error, term()}
  @callback health_check() :: :ok | {:error, term()}
  @callback validate_config(config :: map()) :: :ok | {:error, String.t()}
end
```

## Database Operations Mapping

### Current Database Operations (Agent Web)

**1. Run Management** (`AgentWeb.Llm.RunStoreEcto`):
- `put/1` - Insert new run record
- `get/1` - Get run by ID  
- `list/1` - List runs with filters
- `mark_started/1` - Update run status to started
- `mark_finished/2` - Update run status to finished
- `mark_failed/3` - Update run status to failed

**2. Memory Management** (`AgentWeb.Memory.*`):
- `AgentWeb.Memory.Store.search/2` - Vector similarity search
- `AgentWeb.Memory.Ingestor.ingest/1` - Store memory chunks
- Direct Repo operations for memory chunks

**3. Profile Management** (Via schemas):
- CRUD operations on `AgentWeb.Schemas.ProfileRecord`
- Direct Repo access in controllers

### Target Database Operations (Agent Infra)

**1. AgentInfra.StoreEcto.RunStore**:
```elixir
defmodule AgentInfra.StoreEcto.RunStore do
  @behaviour AgentCore.Stores.RunStore
  
  # Implement all RunStore callbacks
  # Convert between AgentCore.Runs.RunSnapshot and AgentInfra.Schema.Run
  # Handle all database operations through AgentInfra.Repo
end
```

**2. AgentInfra.StoreEcto.MemoryStore**:
```elixir
defmodule AgentInfra.StoreEcto.MemoryStore do
  @behaviour AgentCore.Stores.MemoryStore
  
  # Implement vector search operations
  # Handle memory chunk storage and retrieval
  # Convert between domain structs and AgentInfra.Schema.MemoryChunk
end
```

**3. AgentInfra.StoreEcto.ProfileStore**:
```elixir
defmodule AgentInfra.StoreEcto.ProfileStore do
  @behaviour AgentCore.Stores.ProfileStore
  
  # Implement profile CRUD operations
  # Convert between AgentCore.Profiles.LLMProfile and AgentInfra.Schema.Profile
end
```

### Database Schema Mapping

**Current Schemas → Target Schemas**:
```
AgentWeb.Schemas.RunRecord                 → AgentInfra.Schema.Run
AgentWeb.Schemas.ProfileRecord             → AgentInfra.Schema.Profile  
AgentWeb.Memory.MemoryChunk                → AgentInfra.Schema.MemoryChunk
AgentWeb.Memory.Chunk                      → AgentInfra.Schema.Chunk
```

**Migration Files to Move**:
```
20251220095944_create_llm_runs.exs         → AgentInfra (runs table)
20251220105534_add_run_lifecycle_fields.exs → AgentInfra (runs table updates)
20251221052625_create_llm_profiles.exs     → AgentInfra (profiles table)
20251225041904_rebuild_llm_runs_add_run_id_and_correlation_id.exs → AgentInfra
20251227202558_enable_vector.exs           → AgentInfra (vector extension)
20251227202618_create_conversations.exs    → AgentInfra (conversations table)
20251227202630_create_conversation_messages.exs → AgentInfra (messages table)
20251227202652_create_memory_chunks.exs    → AgentInfra (memory chunks table)
20251228203850_create_vector_extension.exs → AgentInfra (vector extension)
20251230140848_llm_plans.exs               → AgentInfra (plans table)
20251230214444_llm_agents.exs              → AgentInfra (agents table)
20251230215534_add_agent_ref_to_llm_runs.exs → AgentInfra (runs table updates)
```

## Configuration Changes

### App Dependencies

**Current Dependencies**:
```elixir
# agent_core/mix.exs
deps: [
  {:jason, "~> 1.4"},
  {:telemetry, "~> 1.2"},
  # test deps...
]

# agent_runtime/mix.exs  
deps: [
  {:agent_core, in_umbrella: true},
  {:finch, "~> 0.19"},
  {:jason, "~> 1.4"},
  {:ex_json_schema, "~> 0.10"},
  # test deps...
]

# agent_web/mix.exs
deps: [
  {:agent_runtime, in_umbrella: true},
  {:phoenix, "~> 1.8.1"},
  {:phoenix_ecto, "~> 4.5"},
  {:ecto_sql, "~> 3.13"},
  {:postgrex, ">= 0.0.0"},
  {:pgvector, "~> 0.3.1"},
  # other web deps...
]
```

**Target Dependencies**:
```elixir
# agent_core/mix.exs (NO Ecto dependencies)
deps: [
  {:jason, "~> 1.4"},
  {:telemetry, "~> 1.2"},
  # test deps...
]

# agent_runtime/mix.exs (NO Ecto dependencies)
deps: [
  {:agent_core, in_umbrella: true},
  {:finch, "~> 0.19"},
  {:jason, "~> 1.4"},
  {:ex_json_schema, "~> 0.10"},
  # test deps...
]

# agent_infra/mix.exs (ALL Ecto dependencies)
deps: [
  {:agent_core, in_umbrella: true},
  {:ecto_sql, "~> 3.13"},
  {:postgrex, ">= 0.0.0"},
  {:pgvector, "~> 0.3.1"},
  # test deps...
]

# agent_web/mix.exs (NO Ecto dependencies)
deps: [
  {:agent_runtime, in_umbrella: true},
  {:phoenix, "~> 1.8.1"},
  {:phoenix_html, "~> 4.1"},
  {:phoenix_live_view, "~> 1.1.0"},
  # other web deps (no ecto)...
]

# test_assessment_app/mix.exs
deps: [
  {:agent_core, in_umbrella: true},
  {:jason, "~> 1.4"},
  # test deps...
]
```

### Runtime Configuration

**Store Implementation Configuration**:
```elixir
# config/config.exs
config :agent_runtime,
  run_store: AgentInfra.StoreEcto.RunStore,
  profile_store: AgentInfra.StoreEcto.ProfileStore,
  plan_store: AgentInfra.StoreEcto.PlanStore,
  memory_store: AgentInfra.StoreEcto.MemoryStore,
  conversation_store: AgentInfra.StoreEcto.ConversationStore

# config/test.exs (for testing with in-memory stores)
config :agent_runtime,
  run_store: AgentRuntime.Stores.InMemoryRunStore,
  profile_store: AgentRuntime.Stores.InMemoryProfileStore,
  # ... other test stores
```

## API Preservation Requirements

### Web API Endpoints (Must Remain Identical)

**Current Agent Web Controllers**:
- All existing API endpoints must return identical responses
- HTTP status codes must remain the same
- Response JSON structure must be preserved
- Error handling behavior must be identical

**Controller Updates Required**:
```elixir
# Before (agent_web controller)
def create(conn, params) do
  case AgentWeb.Llm.RunStoreEcto.put(run_snapshot) do
    {:ok, run_id} -> json(conn, %{run_id: run_id})
    {:error, reason} -> put_status(conn, 422) |> json(%{error: reason})
  end
end

# After (agent_web controller)  
def create(conn, params) do
  case AgentRuntime.Agent.execute_request(params) do
    {:ok, result} -> json(conn, result)
    {:error, reason} -> put_status(conn, 422) |> json(%{error: reason})
  end
end
```

### CLI Interface (Must Remain Identical)

**Test Assessment CLI**:
- All existing Mix tasks must work unchanged
- Command-line arguments must be preserved
- Output format must be identical
- Exit codes must remain the same

**Migration Path**:
```elixir
# Before
mix test_assessment.run --format json

# After (same command, different implementation)
mix test_assessment.run --format json
```

### Workflow Execution (Must Remain Identical)

**Workflow Results**:
- Workflow execution must produce identical results
- Execution traces must have same structure
- Error handling must be preserved
- Performance characteristics should be maintained

## Migration Validation Strategy

### 1. Pre-Migration State Capture
- Capture all API responses for test suite
- Record workflow execution results
- Document CLI output formats
- Benchmark performance characteristics

### 2. Post-Migration Validation
- Compare API responses byte-for-byte
- Validate workflow results are identical
- Verify CLI output matches exactly
- Confirm performance within acceptable range

### 3. Rollback Procedures
- Maintain complete backup of original structure
- Document rollback steps for each migration phase
- Test rollback procedures in staging environment
- Prepare emergency rollback scripts

## Implementation Order

### Phase 1: Infrastructure Setup
1. Create `agent_infra` app structure
2. Move database schemas and migrations
3. Create store implementations
4. Test database operations

### Phase 2: Domain Layer Cleanup  
1. Remove Ecto dependencies from `agent_core`
2. Update type definitions (remove `Ecto.UUID`)
3. Clean up behavior interfaces
4. Create new behavior definitions

### Phase 3: Runtime Layer Updates
1. Move workflow engine implementations to `agent_runtime`
2. Create store behavior wrappers
3. Implement main Agent orchestrator
4. Update provider implementations

### Phase 4: Web Layer Updates
1. Remove direct database access from `agent_web`
2. Update controllers to use `AgentRuntime` APIs
3. Remove Ecto dependencies
4. Test all web endpoints

### Phase 5: Test Assessment Migration
1. Create `test_assessment_app` structure
2. Move all TestAssessment modules
3. Update namespaces and references
4. Migrate CLI and Mix tasks

### Phase 6: Integration and Validation
1. Test cross-layer communication
2. Validate backward compatibility
3. Performance testing
4. Documentation updates

## Risk Mitigation

### High-Risk Areas
1. **Database Migration**: Complex schema moves with data preservation
2. **API Compatibility**: Ensuring identical responses after refactoring
3. **Workflow Execution**: Maintaining deterministic behavior
4. **Configuration Management**: Complex dependency injection setup

### Mitigation Strategies
1. **Incremental Migration**: Migrate one layer at a time with validation
2. **Comprehensive Testing**: Property-based tests for all correctness properties
3. **Rollback Procedures**: Tested rollback for each migration phase
4. **Staging Validation**: Full system testing in staging environment

### Success Criteria
1. All existing tests pass without modification
2. API responses are byte-for-byte identical
3. Workflow execution produces same results
4. CLI interface works unchanged
5. Performance within 10% of original system
6. Clean dependency flow (no circular dependencies)
7. All Ecto code isolated to `agent_infra` only