# Module Dependency Analysis

## Current Module Structure Analysis

### Agent Core (`apps/agent_core`)

#### Domain Boundaries Identified

**1. LLM Domain (`AgentCore.Llm.*`)**
- **Domain Models**: 
  - `AgentCore.Llm.Runs` - Run management API
  - `AgentCore.Llm.LLMProfile` - LLM configuration profiles
  - `AgentCore.Llm.Provider` - Provider configuration
  - `AgentCore.Llm.RunSnapshot` - Run state snapshots
  - `AgentCore.Llm.GenerationParams` - LLM generation parameters
  - `AgentCore.Llm.Budgets` - Resource budgets
  - `AgentCore.Llm.ModelRef` - Model references

- **Store Behaviors** (Already defined):
  - `AgentCore.Llm.RunStore` - Run persistence behavior
  - `AgentCore.Llm.ProfileStore` - Profile persistence behavior
  - `AgentCore.Llm.PlanStore` - Plan persistence behavior

- **Provider Contracts**:
  - `AgentCore.Llm.ProviderContract` - Provider behavior definition
  - `AgentCore.Llm.ProviderAdapter` - Provider adaptation logic
  - `AgentCore.Llm.ProviderRequest/Response` - Request/response structs

- **Infrastructure Dependencies Found**:
  - `Ecto.UUID` types in `RunStore` and `RunSnapshots` modules
  - Commented-out Ecto implementations in `run_store/ecto.ex` and `profile_store/ecto.ex`

**2. Workflow Engine Domain (`AgentCore.WorkflowEngine.*`)**
- **Domain Models**:
  - `AgentCore.WorkflowEngine.Spec` - Workflow specifications
  - `AgentCore.WorkflowEngine.Context` - Execution context
  - `AgentCore.WorkflowEngine.Step` - Step definitions
  - `AgentCore.WorkflowEngine.WorkflowResult` - Execution results

- **Engine Components**:
  - `AgentCore.WorkflowEngine.Runtime` - Execution engine
  - `AgentCore.WorkflowEngine.Compiler` - Workflow compilation
  - `AgentCore.WorkflowEngine.Registry` - Workflow registry
  - `AgentCore.WorkflowEngine.Agent` - Agent orchestration

- **LLM Integration**:
  - `AgentCore.WorkflowEngine.LlmIntegration` - LLM integration logic

**3. Test Assessment Domain (`AgentCore.TestAssessment.*`)**
- **Complete Domain** (25+ modules):
  - Assessment reports, categorization, CLI interface
  - Coverage analysis, optimization, recommendation engine
  - File discovery, parsing, redundancy detection
  - All modules are self-contained domain logic

### Agent Runtime (`apps/agent_runtime`)

#### Current Structure
- **Flows**: `AgentRuntime.Flows.*`
- **LLM**: `AgentRuntime.Llm.*` 
- **Memory**: `AgentRuntime.Memory.*`
- **Plan**: `AgentRuntime.Plan.*`
- **Providers**: `AgentRuntime.Providers.*`
- **Workflow Engine**: `AgentRuntime.WorkflowEngine.*`

#### Dependencies
- Depends on `agent_core` (correct)
- Uses `finch` for HTTP requests
- Uses `jason` for JSON handling
- Uses `ex_json_schema` for validation

### Agent Web (`apps/agent_web`)

#### Current Database Usage
- **Direct Ecto Usage Found**:
  - `AgentWeb.Repo` - Main repository
  - `AgentWeb.Schemas.RunRecord` - Run database schema
  - `AgentWeb.Schemas.ProfileRecord` - Profile database schema
  - `AgentWeb.Memory.MemoryChunk` - Memory storage schema
  - `AgentWeb.Memory.Chunk` - Memory chunk schema
  - `AgentWeb.Llm.RunStoreEcto` - Ecto-based run store implementation

#### Dependencies
- Depends on `agent_runtime` (correct)
- Has Ecto dependencies: `ecto_sql`, `postgrex`, `phoenix_ecto`
- Direct database access through `Repo`

## Target Layer Mapping

### 1. Agent Core (Domain Layer)
**Target**: Pure domain models, behaviors, contracts - NO infrastructure dependencies

**Modules to Keep**:
- All domain structs: `LLMProfile`, `Provider`, `RunSnapshot`, etc.
- All behavior definitions: `RunStore`, `ProfileStore`, `ProviderContract`
- All domain logic: validation, state machines, business rules
- Workflow specifications and domain models

**Modules to Clean**:
- Remove `Ecto.UUID` type references - use `String.t()` for IDs
- Remove commented Ecto implementations
- Keep only behavior definitions, not implementations

### 2. Agent Runtime (Runtime Layer)  
**Target**: Behavior implementations, execution engines, orchestration

**Modules to Keep/Move Here**:
- All current `AgentRuntime.*` modules
- Workflow execution engines from `AgentCore.WorkflowEngine.Runtime`
- Agent orchestration from `AgentCore.WorkflowEngine.Agent`
- Provider HTTP clients and implementations
- Tool executors and registries

**New Modules Needed**:
- Store behavior wrappers that delegate to configured implementations
- Main `AgentRuntime.Agent` orchestrator
- Workflow engine implementations

### 3. Agent Infra (Infrastructure Layer)
**Target**: All database/persistence concerns - ONLY app with Ecto

**Modules to Move Here**:
- `AgentWeb.Repo` → `AgentInfra.Repo`
- `AgentWeb.Schemas.*` → `AgentInfra.Schema.*`
- `AgentWeb.Llm.RunStoreEcto` → `AgentInfra.StoreEcto.RunStore`
- All migrations from `agent_web/priv/repo/migrations`

**New Modules Needed**:
- Store implementations for all behaviors defined in `agent_core`
- Conversion functions between domain structs and Ecto schemas
- Database-specific logic and optimizations

### 4. Agent Web (Web Layer)
**Target**: HTTP/Phoenix concerns only - NO direct database access

**Modules to Keep**:
- All controllers, views, templates
- Phoenix-specific modules
- API endpoints and routing

**Modules to Remove**:
- All `AgentWeb.Schemas.*` → move to `agent_infra`
- All direct `Repo` usage → call `AgentRuntime` APIs instead
- `AgentWeb.Memory.*` database logic → move to `agent_infra`

### 5. Test Assessment App (Separate Domain)
**Target**: Independent app following same architecture

**Modules to Move**:
- All `AgentCore.TestAssessment.*` → `TestAssessmentApp.*`
- `Mix.Tasks.TestAssessment` → `TestAssessmentApp.Mix.Tasks.*`
- Related tests and configurations

## Ecto Dependencies Analysis

### Current Ecto Usage
1. **Agent Core**: Minimal - only type references (`Ecto.UUID`)
2. **Agent Runtime**: None - clean
3. **Agent Web**: Heavy - schemas, repo, migrations, direct queries

### Target Ecto Usage
1. **Agent Core**: None - remove all Ecto references
2. **Agent Runtime**: None - maintain clean separation  
3. **Agent Infra**: All - only app with Ecto dependencies
4. **Agent Web**: None - remove all direct database access

## Database Operations Mapping

### Current Database Operations in Agent Web
1. **Run Management**: `AgentWeb.Llm.RunStoreEcto`
2. **Memory Storage**: `AgentWeb.Memory.Store`, `AgentWeb.Memory.Ingestor`
3. **Profile Management**: Via `AgentWeb.Schemas.ProfileRecord`

### Target Store Behaviors (Agent Core)
```elixir
# Already defined behaviors that need implementations:
AgentCore.Llm.RunStore
AgentCore.Llm.ProfileStore  
AgentCore.Llm.PlanStore

# New behaviors needed:
AgentCore.Stores.MemoryStore
AgentCore.Stores.WorkflowStore
```

### Target Store Implementations (Agent Infra)
```elixir
# Ecto implementations:
AgentInfra.StoreEcto.RunStore
AgentInfra.StoreEcto.ProfileStore
AgentInfra.StoreEcto.PlanStore
AgentInfra.StoreEcto.MemoryStore
AgentInfra.StoreEcto.WorkflowStore
```

## Migration Complexity Assessment

### Low Complexity
- **Test Assessment**: Self-contained domain, minimal dependencies
- **Domain Models**: Already well-structured, minimal changes needed

### Medium Complexity  
- **Workflow Engine**: Some runtime logic mixed with domain models
- **Provider System**: Clean contracts but implementations scattered

### High Complexity
- **Database Layer**: Heavy refactoring needed to separate concerns
- **Web Layer**: Remove all direct database access, update to use runtime APIs
- **Store Implementations**: Create new infrastructure layer with all Ecto code

## Dependencies That Must Be Preserved

### API Contracts
- All existing public APIs must remain identical
- Workflow execution results must be identical
- Test assessment CLI must work unchanged
- Web endpoints must return same responses

### Behavior Interfaces
- All existing behavior definitions in `AgentCore.Llm.*Store`
- Provider contracts and request/response formats
- Workflow specification format and execution semantics

### Configuration
- Application configuration structure
- Environment variable usage
- Deployment characteristics