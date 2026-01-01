# Requirements Document

## Introduction

This document specifies the requirements for restructuring the current Phoenix umbrella application to separate workflow-related implementation and test-assessment functionality into dedicated umbrella apps. The goal is to create a more modular, maintainable, and expandable architecture where the agent can include workflows from multiple specialized apps, making the system easily extensible for future workflow types.

## Glossary

- **Umbrella_Restructure**: The process of reorganizing code into separate umbrella applications
- **Workflow_App**: A dedicated umbrella app containing all workflow engine and workflow-specific implementations
- **Test_Assessment_App**: A dedicated umbrella app containing all test assessment functionality
- **Agent_Core**: The main application that coordinates and integrates functionality from other apps
- **Cross_App_Integration**: The mechanism by which apps communicate and share functionality within the umbrella
- **Module_Migration**: The process of moving modules from one app to another while maintaining functionality
- **Dependency_Management**: The configuration of inter-app dependencies within the umbrella structure
- **Interface_Contracts**: Well-defined APIs between apps to ensure clean separation of concerns

## Requirements

### Requirement 1

**User Story:** As a system architect, I want to separate domain logic from infrastructure concerns, so that the system follows clean architecture principles with proper dependency inversion.

#### Acceptance Criteria

1. WHEN the restructure is complete THEN agent_core SHALL contain only domain models, contracts, and behaviors with no infrastructure dependencies
2. WHEN the restructure is complete THEN agent_core SHALL have no Ecto, no Repo, and no migrations
3. WHEN the restructure is complete THEN all domain logic SHALL be located in agent_core with clear separation between Runs, Profiles, Providers, Workflows, and Tools domains
4. WHEN the restructure is complete THEN agent_core SHALL define store ports/behaviors that infrastructure can implement
5. WHEN the restructure is complete THEN agent_core SHALL be the dependency target for all other layers

### Requirement 2

**User Story:** As a system architect, I want a dedicated runtime layer that implements domain behaviors, so that execution logic is separated from domain definitions and infrastructure concerns.

#### Acceptance Criteria

1. WHEN the restructure is complete THEN agent_runtime SHALL implement all behaviors defined in agent_core
2. WHEN the restructure is complete THEN agent_runtime SHALL contain execution engines and orchestration logic
3. WHEN the restructure is complete THEN agent_runtime SHALL see only behaviors/interfaces of stores, not Ecto schemas
4. WHEN the restructure is complete THEN agent_runtime SHALL provide the main Agent executor that orchestrates requests
5. WHEN the restructure is complete THEN agent_runtime SHALL implement workflow engines, tool executors, and provider clients

### Requirement 3

**User Story:** As a system architect, I want a dedicated infrastructure layer for all database and persistence concerns, so that infrastructure details are completely isolated from business logic.

#### Acceptance Criteria

1. WHEN the restructure is complete THEN agent_infra SHALL be the only app with Ecto dependencies
2. WHEN the restructure is complete THEN agent_infra SHALL contain all database schemas, migrations, and the Repo
3. WHEN the restructure is complete THEN agent_infra SHALL implement the store behaviors defined in agent_core
4. WHEN the restructure is complete THEN agent_infra SHALL provide conversion between domain structs and database schemas
5. WHEN the restructure is complete THEN agent_infra SHALL handle all database operations and persistence logic

### Requirement 4

**User Story:** As a developer, I want the web layer to only call runtime APIs, so that the web interface is decoupled from infrastructure and domain concerns.

#### Acceptance Criteria

1. WHEN the restructure is complete THEN agent_web SHALL only call AgentRuntime public APIs
2. WHEN the restructure is complete THEN agent_web SHALL not touch the Repo directly
3. WHEN the restructure is complete THEN agent_web SHALL not import any agent_infra modules
4. WHEN the restructure is complete THEN agent_web SHALL maintain all existing API endpoints with identical behavior
5. WHEN the restructure is complete THEN agent_web SHALL handle HTTP concerns only, delegating all business logic to agent_runtime

### Requirement 5

**User Story:** As a system architect, I want test assessment functionality to remain as a separate domain, so that it can be developed independently while following the same architectural principles.

#### Acceptance Criteria

1. WHEN the restructure is complete THEN all TestAssessment modules SHALL be located in test_assessment_app
2. WHEN the restructure is complete THEN test_assessment_app SHALL follow the same clean architecture principles as the main system
3. WHEN the restructure is complete THEN test_assessment_app SHALL have its own domain models and behaviors
4. WHEN the restructure is complete THEN test_assessment_app SHALL be accessible through well-defined interfaces
5. WHEN the restructure is complete THEN test_assessment_app CLI and Mix tasks SHALL continue to work identically

### Requirement 6

**User Story:** As a developer, I want proper dependency management with clean dependency flow, so that the architecture maintains proper separation of concerns and testability.

#### Acceptance Criteria

1. WHEN dependencies are configured THEN agent_web SHALL depend on agent_runtime only
2. WHEN dependencies are configured THEN agent_runtime SHALL depend on agent_core only  
3. WHEN dependencies are configured THEN agent_infra SHALL depend on agent_core only
4. WHEN dependencies are configured THEN no circular dependencies SHALL exist between apps
5. WHEN dependencies are configured THEN the build system SHALL compile apps in correct dependency order

### Requirement 7

**User Story:** As a developer, I want all existing functionality to continue working after the restructure, so that the system maintains backward compatibility and existing integrations remain functional.

#### Acceptance Criteria

1. WHEN the restructure is complete THEN all existing API endpoints SHALL continue to function identically
2. WHEN workflows are executed THEN they SHALL produce the same results as before the restructure
3. WHEN test assessments are run THEN they SHALL generate identical reports to the pre-restructure implementation
4. WHEN integration tests are run THEN they SHALL pass without requiring changes to test expectations
5. WHEN the system is deployed THEN all existing functionality SHALL work without modification

### Requirement 8

**User Story:** As a developer, I want comprehensive testing to ensure the restructure doesn't break existing functionality, so that I can confidently deploy the restructured system.

#### Acceptance Criteria

1. WHEN the restructure is complete THEN all existing unit tests SHALL pass without modification
2. WHEN integration tests are run THEN they SHALL verify cross-layer communication works correctly
3. WHEN property-based tests are executed THEN they SHALL continue to validate system correctness
4. WHEN end-to-end tests are run THEN they SHALL confirm complete system functionality
5. WHEN performance tests are executed THEN they SHALL show no significant regression in system performance

### Requirement 9

**User Story:** As a system operator, I want the restructured system to maintain the same deployment and operational characteristics, so that existing infrastructure and processes continue to work.

#### Acceptance Criteria

1. WHEN the system is built THEN the final release SHALL have the same structure and entry points
2. WHEN the system is deployed THEN it SHALL use the same configuration files and environment variables
3. WHEN the system runs THEN it SHALL have the same resource requirements and performance characteristics
4. WHEN monitoring is applied THEN existing monitoring and logging SHALL continue to work
5. WHEN the system is scaled THEN it SHALL maintain the same scaling characteristics and bottlenecks

### Requirement 10

**User Story:** As a future developer, I want clear documentation of the new architecture, so that I can understand how to add new functionality and maintain the system.

#### Acceptance Criteria

1. WHEN the restructure is complete THEN architecture documentation SHALL be updated to reflect the new layered structure
2. WHEN new developers join THEN they SHALL have clear guidance on which layer contains which functionality
3. WHEN new features are added THEN there SHALL be documented patterns for maintaining clean architecture
4. WHEN integration is needed THEN there SHALL be clear examples of how layers communicate
5. WHEN troubleshooting is required THEN there SHALL be documentation of layer dependencies and communication flows