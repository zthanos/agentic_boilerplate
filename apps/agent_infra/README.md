# AgentInfra

AgentInfra is the infrastructure layer of the Agent system, responsible for all database and persistence concerns.

## Features

- Ecto repository and database management
- Database schemas and migrations
- Store behavior implementations
- Data persistence and retrieval logic

## Architecture

This app follows the hexagonal architecture pattern, implementing the store behaviors defined in `agent_core` and providing concrete database implementations using Ecto and PostgreSQL.

## Dependencies

- `agent_core` - Domain models and store behaviors
- `ecto` - Database toolkit
- `ecto_sql` - SQL adapter for Ecto
- `postgrex` - PostgreSQL driver

## Configuration

Database configuration is managed through environment-specific config files in the `config/` directory.