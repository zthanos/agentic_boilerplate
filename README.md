# Agent System - Hexagonal Architecture

This repository implements an **agentic AI system** using **Hexagonal Architecture** principles within an **Elixir Umbrella application**. The system is designed for experimenting with agentic AI patterns (Reflection, Planning, Tool Usage) while maintaining clean separation of concerns and high testability.

## Architecture Overview

The system follows **Hexagonal Architecture** (Ports and Adapters) with clear layer separation:

- **Domain Layer** (`agent_core`): Pure business logic, no external dependencies
- **Runtime Layer** (`agent_runtime`): Orchestration and behavior implementations  
- **Infrastructure Layer** (`agent_infra`): Database, persistence, external services
- **Web Layer** (`agent_web`): HTTP interfaces, Phoenix controllers and LiveViews
- **Test Assessment** (`test_assessment_app`): Separate domain for test analysis

## Key Benefits

- **Clean Architecture**: Domain logic isolated from infrastructure concerns
- **Testability**: Each layer can be tested independently with clear contracts
- **Flexibility**: Infrastructure can be swapped without affecting business logic
- **Maintainability**: Clear boundaries make the system easy to understand and modify
- **Scalability**: Teams can work on different layers independently

## Project Structure


```
apps/
├── agent_core/          # Domain Layer - Pure business logic
│   ├── lib/agent_core/
│   │   ├── runs.ex           # Runs domain
│   │   ├── profiles.ex       # Profiles domain  
│   │   ├── workflows.ex      # Workflows domain
│   │   ├── tools.ex          # Tools domain
│   │   ├── providers.ex      # Providers domain
│   │   └── stores/           # Port definitions (behaviors)
│   └── test/
├── agent_runtime/       # Runtime Layer - Orchestration & execution
│   ├── lib/agent_runtime/
│   │   ├── agent.ex          # Main orchestrator
│   │   ├── workflows/        # Workflow engine implementation
│   │   ├── tools/            # Tool execution
│   │   └── providers/        # Provider clients
│   └── test/
├── agent_infra/         # Infrastructure Layer - Database & persistence
│   ├── lib/agent_infra/
│   │   ├── repo.ex           # Ecto repository
│   │   ├── schema/           # Database schemas
│   │   └── store_ecto/       # Store implementations
│   ├── priv/repo/migrations/ # Database migrations
│   └── test/
├── agent_web/           # Web Layer - HTTP interfaces
│   ├── lib/agent_web/
│   │   ├── controllers/      # HTTP controllers
│   │   ├── live/             # LiveViews
│   │   └── api/              # API endpoints
│   └── test/
└── test_assessment_app/ # Separate Domain - Test assessment
    ├── lib/test_assessment_app/
    │   ├── core.ex           # Assessment logic
    │   ├── cli.ex            # CLI interface
    │   └── mix/tasks/        # Mix tasks
    └── test/
```

## Dependency Flow

Dependencies flow **inward** toward the domain:

```
agent_web     → agent_runtime → agent_core
agent_infra   → agent_core
test_assessment_app → agent_core
```

**Rules**:
- ❌ `agent_core` has no dependencies on other apps
- ❌ No circular dependencies between apps
- ✅ Infrastructure implements domain contracts (behaviors)
- ✅ Web layer only calls runtime APIs

## Quick Start

### Prerequisites
- Elixir 1.15+
- Phoenix 1.7+
- SQLite3

### Development Setup

1. **Clone and setup**:
   ```bash
   git clone <repository>
   cd agent-system
   mix deps.get
   ```

2. **Database setup**:
   ```bash
   mix ecto.create
   mix ecto.migrate
   mix run apps/agent_web/priv/repo/seeds.exs
   ```

3. **Start the system**:
   ```bash
   mix phx.server
   ```

4. **Access the application**:
   - Web UI: http://localhost:4000
   - API Documentation: http://localhost:4000/api/swaggerui

### Docker Setup

```bash
docker-compose up -d
```

Access at http://localhost:8080

## Architecture Documentation

For detailed architecture information:

- **[Architecture Overview](doc/architecture.md)** - Complete system architecture
- **[Dependency Flow](doc/dependency-flow.md)** - Layer communication patterns  
- **[Developer Guide](doc/developer-guide.md)** - How to add new features
- **[Layer Communication](doc/layer-communication.md)** - Communication examples

## Core Concepts

### Domain Layer (agent_core)
Pure business logic with no external dependencies:
- Domain models (Runs, Profiles, Workflows, Tools, Providers)
- Business rule validation
- Port definitions (behaviors) for external services

### Runtime Layer (agent_runtime)  
Orchestration and behavior implementations:
- Main Agent executor
- Workflow engine implementation
- Tool execution and registry
- Provider clients (LLM, external APIs)

### Infrastructure Layer (agent_infra)
Database and persistence concerns:
- Ecto repository and schemas
- Store behavior implementations
- Database migrations
- Data conversion between domain and database models

### Web Layer (agent_web)
HTTP interfaces and user interactions:
- Phoenix controllers and LiveViews
- REST API endpoints
- Web UI for monitoring and interaction
- OpenAPI documentation

## Testing Strategy

The system uses a comprehensive testing approach:

- **Unit Tests**: Test each layer in isolation
- **Integration Tests**: Test cross-layer communication
- **Property-Based Tests**: Validate system correctness properties
- **Contract Tests**: Ensure behavior implementations match contracts

Run tests:
```bash
# All tests
mix test

# Specific app tests  
mix test apps/agent_core
mix test apps/agent_runtime
mix test apps/agent_infra
mix test apps/agent_web
```

## API Usage

### Execute Agent Request
```bash
curl -X POST http://localhost:4000/api/llm/execute \
  -H "Content-Type: application/json" \
  -d '{
    "profile_id": "default_llm",
    "input": {
      "type": "chat",
      "messages": [{"role": "user", "content": "Hello!"}]
    },
    "overrides": {}
  }'
```

### List Runs
```bash
curl http://localhost:4000/api/runs
```

### Get Specific Run
```bash
curl http://localhost:4000/api/runs/{run_id}
```

## Configuration

### LLM Providers
Configure in `config/config.exs`:
```elixir
config :agent_runtime, :providers,
  openai_compatible: [
    base_url: "http://localhost:1234/v1",
    api_key: nil,  # Optional for local providers
    timeout: 30_000
  ]
```

### Store Implementations
```elixir
config :agent_runtime, :stores,
  run_store: AgentInfra.StoreEcto.RunStore,
  profile_store: AgentInfra.StoreEcto.ProfileStore
```

## Development Guidelines

### Adding New Features

1. **Start with Domain**: Define domain models and behaviors in `agent_core`
2. **Implement Runtime**: Create behavior implementations in `agent_runtime`  
3. **Add Infrastructure**: Implement persistence in `agent_infra`
4. **Expose via Web**: Add controllers/LiveViews in `agent_web`

### Layer Rules

- **Domain Layer**: No external dependencies, pure business logic
- **Runtime Layer**: Only depends on domain, implements behaviors
- **Infrastructure Layer**: Only depends on domain, implements persistence
- **Web Layer**: Only depends on runtime, handles HTTP concerns

## Contributing

1. Follow the architectural principles
2. Maintain clean layer separation
3. Write tests for all new functionality
4. Update documentation for architectural changes

## License

[Add your license information here]