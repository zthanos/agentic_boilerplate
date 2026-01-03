# Implementation Plan: Umbrella Restructure

## Overview

This implementation plan restructures the Phoenix umbrella application to follow clean hexagonal architecture principles with proper separation between domain, runtime, infrastructure, and web layers.

## Tasks

- [x] 1. Preparation and dependency analysis
  - Analyze current module dependencies and identify domain boundaries
  - Create detailed migration mapping from current structure to new layered architecture
  - Document all existing APIs and behaviors that must be preserved
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

- [x] 1.1 Analyze current module structure and dependencies
  - Scan all modules in agent_core to identify domain boundaries
  - Map current modules to target layers (core/runtime/infra)
  - Identify all Ecto dependencies and database operations
  - _Requirements: 1.1, 1.2, 2.1, 3.1_

- [x] 1.2 Create migration mapping document
  - Document which modules move to which apps
  - Identify all behavior interfaces that need to be created
  - Map current database operations to store behaviors
  - _Requirements: 1.3, 1.4, 2.2, 3.2_

- [ ]* 1.3 Write property test for dependency analysis accuracy
  - **Property 1: Module migration completeness**
  - **Validates: Requirements 1.1, 1.2, 1.3**

- [x] 2. Create new app structures and initial configurations
  - Set up directory structures for agent_core, agent_runtime, agent_infra
  - Create mix.exs files with proper dependency declarations
  - Configure compilation order and app dependencies
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

- [x] 2.1 Create agent_core app structure
  - Create apps/agent_core directory with lib, test subdirectories
  - Create mix.exs with no Ecto dependencies
  - Set up basic application module and supervision tree
  - _Requirements: 1.1, 1.2_

- [x] 2.2 Create agent_runtime app structure
  - Create apps/agent_runtime directory with proper structure
  - Create mix.exs depending only on agent_core
  - Configure runtime application with proper dependencies
  - _Requirements: 2.1, 2.2, 6.2_

- [x] 2.3 Create agent_infra app structure
  - Create apps/agent_infra directory for database concerns
  - Create mix.exs with Ecto dependencies and agent_core dependency
  - Set up Repo and basic database configuration
  - _Requirements: 3.1, 3.2, 6.3_

- [ ]* 2.4 Write property test for app configuration correctness
  - **Property 2: App configuration correctness**
  - **Validates: Requirements 6.1, 6.2, 6.3, 6.4, 6.5**

- [x] 3. Extract domain models and behaviors to agent_core
  - Move all domain structs and business logic to agent_core
  - Create behavior definitions for stores and external services
  - Remove all infrastructure dependencies from domain code
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

- [x] 3.1 Create domain modules for Runs, Profiles, Providers, Workflows, Tools
  - Extract and clean up domain structs from current agent_core
  - Create proper domain modules with validation and business logic
  - Define state machines and domain events where needed
  - _Requirements: 1.1, 1.3_

- [x] 3.2 Define store behavior interfaces
  - Create AgentCore.Stores.RunStore behavior
  - Create AgentCore.Stores.ProfileStore behavior
  - Define all necessary CRUD and query operations as behaviors
  - _Requirements: 1.4, 3.4_

- [x] 3.3 Create provider and workflow behaviors
  - Define AgentCore.Providers.Behavior for external integrations
  - Create AgentCore.Workflows.Engine behavior for workflow execution
  - Define AgentCore.Tools.Behavior for tool implementations
  - _Requirements: 1.5, 2.4_

- [ ]* 3.4 Write property test for domain model purity
  - **Property 3: Cross-app integration functionality**
  - **Validates: Requirements 1.4, 1.5**

- [x] 4. Checkpoint - Ensure domain layer is clean
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Create infrastructure layer in agent_infra
  - Move all Ecto schemas and database operations to agent_infra
  - Implement store behaviors defined in agent_core
  - Create conversion functions between domain and database models
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [x] 5.1 Move Ecto schemas to agent_infra
  - Create AgentInfra.Schema modules for all database entities
  - Move all migrations to agent_infra/priv/repo/migrations
  - Set up AgentInfra.Repo as the only database access point
  - _Requirements: 3.1, 3.2_

- [x] 5.2 Implement store behaviors
  - Create AgentInfra.StoreEcto.RunStore implementing AgentCore.Stores.RunStore
  - Implement all other store behaviors with proper error handling
  - Add conversion functions between domain structs and Ecto schemas
  - _Requirements: 3.3, 3.4_

- [ ]* 5.3 Write property test for store behavior implementations
  - **Property 4: API boundary enforcement**
  - **Validates: Requirements 3.3, 3.4**

- [x] 6. Update agent_runtime to use behaviors
  - Update agent_runtime to implement domain behaviors from agent_core
  - Remove direct Ecto dependencies and use store behaviors instead
  - Create execution engines and orchestration logic
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

- [x] 6.1 Implement workflow engine in agent_runtime
  - Create AgentRuntime.Workflows.Engine implementing AgentCore.Workflows.Engine
  - Move workflow execution logic from current location
  - Update to use store behaviors for persistence
  - _Requirements: 2.1, 2.3_

- [x] 6.2 Create main Agent executor
  - Implement AgentRuntime.Agent as main orchestration point
  - Create request routing and execution coordination
  - Integrate with all domain engines (workflows, tools, providers)
  - _Requirements: 2.2, 2.4_

- [x] 6.3 Update provider and tool implementations
  - Move provider HTTP clients to agent_runtime
  - Implement tool execution and registry in agent_runtime
  - Ensure all implementations use store behaviors for persistence
  - _Requirements: 2.3, 2.5_

- [ ]* 6.4 Write property test for runtime behavior implementations
  - **Property 5: Dependency management correctness**
  - **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5**

- [x] 7. Update agent_web to use only runtime APIs
  - Remove all direct database access from agent_web
  - Update controllers to call only AgentRuntime APIs
  - Ensure all existing endpoints continue to work identically
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

- [x] 7.1 Update web controllers
  - Modify all controllers to call AgentRuntime.Agent instead of direct services
  - Remove any agent_infra imports or direct Repo calls
  - Maintain identical API responses and error handling
  - _Requirements: 4.1, 4.2, 4.3_

- [x] 7.2 Update LiveViews and web components
  - Update any LiveViews to use AgentRuntime APIs
  - Ensure web layer has no infrastructure dependencies
  - Test all web functionality works identically
  - _Requirements: 4.4, 4.5_

- [ ]* 7.3 Write property test for web layer isolation
  - **Property 6: Test isolation and independence**
  - **Validates: Requirements 4.1, 4.2, 4.3, 4.4, 4.5**

- [x] 8. Migrate test assessment to separate app
  - Create test_assessment_app with all TestAssessment modules
  - Update namespaces to TestAssessmentApp.*
  - Migrate CLI and Mix tasks to new app
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

- [x] 8.1 Create test_assessment_app structure
  - Set up app directory and mix.exs configuration
  - Create proper namespace structure for TestAssessmentApp
  - Set up dependencies and application configuration
  - _Requirements: 5.1, 5.4_

- [x] 8.2 Move TestAssessment modules
  - Move all AgentCore.TestAssessment modules to TestAssessmentApp
  - Update module namespaces and internal references
  - Migrate all related tests to test_assessment_app
  - _Requirements: 5.1, 5.3_

- [x] 8.3 Migrate CLI and Mix tasks
  - Move Mix.Tasks.TestAssessment to TestAssessmentApp
  - Update CLI interface and command-line tools
  - Ensure all existing functionality works identically
  - _Requirements: 5.2, 5.5_

- [ ]* 8.4 Write property test for test assessment migration
  - **Property 7: Agent extensibility and workflow discovery**
  - **Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5**

- [x] 9. Checkpoint - Ensure all layers work correctly
  - Ensure all tests pass, ask the user if questions arise.
  - ✅ **COMPLETED**: All layers validated successfully
    - **Agent Core**: 251 tests + 1 doctest + 6 properties pass - Clean domain layer
    - **Agent Runtime**: 29 tests + 1 doctest pass - Runtime orchestration working
    - **Agent Web**: 5 tests pass - Web layer properly isolated
    - **Test Assessment App**: 14 tests pass - Separate domain functioning
    - **Agent Infra**: 1 test + 1 doctest pass - Database layer operational

- [x] 10. Integration testing and validation
  - Test cross-layer communication and dependency flow
  - Validate all existing functionality works identically
  - Run performance tests to ensure no regressions
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 8.1, 8.2, 8.3, 8.4, 8.5_

- [x] 10.1 Test cross-layer integration
  - Test web → runtime → core → infra communication flow
  - Verify store behaviors work correctly with real database
  - Test error handling and propagation across layers
  - _Requirements: 7.1, 7.2, 8.2_

- [x] 10.2 Validate backward compatibility
  - Run all existing API tests to ensure identical behavior
  - Test workflow execution produces same results
  - Verify test assessment generates identical reports
  - _Requirements: 7.1, 7.2, 7.3_

- [x] 10.3 Performance and regression testing
  - Run performance benchmarks against original system
  - Test system resource usage and scaling characteristics
  - Validate no significant performance regressions
  - _Requirements: 8.5, 9.3_

- [ ]* 10.4 Write property test for backward compatibility
  - **Property 8: Backward compatibility preservation**
  - **Validates: Requirements 7.1, 7.2, 7.3, 7.5**

- [ ]* 10.5 Write property test for system operational equivalence
  - **Property 10: System operational equivalence**
  - **Validates: Requirements 9.1, 9.3**

- [x] 11. Update configuration and deployment
  - Update application configuration for new app structure
  - Ensure deployment processes work with restructured system
  - Update monitoring and logging configuration
  - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5_

- [x] 11.1 Update application configuration
  - Configure store behavior implementations in runtime config
  - Set up proper app startup order and dependencies
  - Update environment-specific configurations
  - _Requirements: 9.1, 9.2_

- [x] 11.2 Test deployment and operations
  - Build and deploy restructured system
  - Verify all existing operational procedures work
  - Test monitoring, logging, and health checks
  - _Requirements: 9.3, 9.4, 9.5_

- [ ]* 11.3 Write integration tests for deployment
  - Test system builds correctly with new structure
  - Verify deployment processes work without modification
  - Test operational characteristics match original system
  - _Requirements: 9.1, 9.2, 9.3_

- [x] 12. Documentation and architecture guides
  - Update architecture documentation to reflect new layered structure
  - Create developer guides for maintaining clean architecture
  - Document layer communication patterns and best practices
  - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_

- [x] 12.1 Update architecture documentation
  - Document the new hexagonal architecture structure
  - Explain domain, runtime, infrastructure, and web layer responsibilities
  - Create diagrams showing dependency flow and communication patterns
  - _Requirements: 10.1, 10.2_

- [x] 12.2 Create developer guides
  - Write guides for adding new features while maintaining clean architecture
  - Document how to create new store behaviors and implementations
  - Provide examples of proper layer communication
  - _Requirements: 10.3, 10.4_

- [ ]* 12.3 Write property test for documentation completeness
  - **Property 11: Documentation completeness**
  - **Validates: Requirements 10.1, 10.3, 10.4, 10.5**

- [x] 13. Final validation and cleanup
  - Run complete test suite across all apps
  - Clean up any temporary migration code
  - Validate system is ready for production deployment
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

- [x] 13.1 Complete system testing
  - Run all unit, integration, and property-based tests
  - Perform end-to-end testing of complete system functionality
  - Validate performance meets requirements
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

- [x] 13.2 Production readiness validation
  - Verify system is ready for production deployment
  - Complete final architecture review
  - Ensure all migration objectives have been met
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

- [x] 14. Final checkpoint - System ready for deployment
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional property-based tests that validate architectural correctness
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation of the restructuring process
- The restructure maintains complete backward compatibility while establishing clean architecture
- All existing APIs and functionality continue to work identically after restructuring