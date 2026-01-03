# Implementation Plan: Agent Testing Interface

## Overview

This implementation plan breaks down the agent testing interface into discrete coding tasks that build incrementally. The approach focuses on creating the core LiveView interface first, then adding workflow visualization, chat integration leveraging existing SSE infrastructure, agent management, and finally the automated testing infrastructure.

**Architecture Focus:**
- **Workflow-Only Architecture**: The system is designed around workflows as the primary execution mechanism. Plans are being phased out in favor of workflows that provide more reliable and consistent responses.
- **No Plan Fallback**: All functionality is built to work directly with workflows without fallback to plan-based execution.

**Key Integration Points:**
- Leverages existing `AgentWeb.Streaming.SseManager` for real-time communication
- Reuses `AgentWebWeb.MessagesComponent` for message rendering and streaming
- Integrates with existing `/api/agents/execute/stream` endpoint
- Uses established SSE event patterns (`sse_token`, `sse_done`, `sse_error`, `sse_clarify`)
- **Multi-Profile Workflow Execution**: Uses agent's configured profiles (execution, assessor, embeddings) for different workflow steps

## Tasks

- [x] 1. Set up core LiveView structure and routing
  - Create AgentTestingLive module with basic mount and render functions
  - Add route to router.ex for the agent testing page
  - Create basic HTML template with placeholder sections for graph and chat
  - Set up initial assigns for agent selection and interface state
  - _Requirements: 1.1_

- [x] 2. Implement agent discovery and selection
  - [x] 2.1 Create agent registry integration
    - Query existing agent registry for available agents
    - Handle empty agent list scenarios
    - Implement agent selection event handling
    - _Requirements: 1.2, 1.4_

  - [ ]* 2.2 Write property test for agent selection
    - **Property 2: Agent Selection and Loading**
    - **Validates: Requirements 1.4**

  - [x] 2.3 Add agent seeding functionality
    - Create AgentSeeder module for creating test agents
    - Implement seeding with workflow-based configuration (no plan references)
    - Add seeding UI controls and event handling
    - _Requirements: 5.1, 5.2, 5.3_

  - [ ]* 2.4 Write property tests for agent seeding
    - **Property 9: Agent Seeding Functionality**
    - **Validates: Requirements 5.2, 5.3, 5.5**

- [x] 3. Create workflow graph visualization component
  - [x] 3.1 Implement WorkflowGraphComponent
    - Create component module with workflow spec rendering
    - Add node and edge visualization using SVG or CSS
    - Implement status-based node coloring (pending, running, completed, failed)
    - Add hover tooltips for step details
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

  - [ ]* 3.2 Write property test for workflow visualization
    - **Property 4: Workflow Graph Visualization**
    - **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5**

  - [x] 3.3 Integrate workflow graph with agent selection
    - Load workflow specifications when agent is selected
    - Update graph display based on selected agent's workflows
    - Handle workflow loading errors gracefully
    - _Requirements: 1.4, 1.5_

- [x] 4. Checkpoint - Ensure basic interface functionality
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Implement chat interface integration
  - [x] 5.1 Create ChatInterfaceComponent wrapper
    - Integrate existing AgentWebWeb.MessagesComponent for message rendering
    - Leverage existing SSE streaming infrastructure and AgentWeb.Streaming.SseManager
    - Add agent-specific metadata to messages
    - Implement message sending via existing /api/agents/execute/stream endpoint
    - _Requirements: 3.1, 3.2, 8.1, 8.2_

  - [ ]* 5.2 Write property tests for chat message processing
    - **Property 5: Chat Message Processing**
    - **Validates: Requirements 3.1, 3.2**

  - [x] 5.3 Add conversation history and context management
    - Maintain conversation state across message exchanges using existing message format
    - Display workflow progress indicators in chat using existing MessagesComponent features
    - Handle streaming responses from agents via AgentWeb.Streaming.SseManager
    - Implement SSE event handlers (sse_token, sse_done, sse_error, sse_clarify)
    - _Requirements: 3.3, 3.4_

  - [ ]* 5.4 Write property test for conversation context
    - **Property 6: Conversation Context Maintenance**
    - **Validates: Requirements 3.3, 3.4**

  - [x] 5.5 Implement chat error handling
    - Display agent errors clearly in chat interface using existing error message patterns
    - Distinguish error messages from normal responses with enhanced formatting
    - Add error recovery options (retry, dismiss) leveraging existing SSE error handling
    - Implement structured error types (timeout, connection, validation) with user-friendly messages
    - _Requirements: 3.5, 1.5_

  - [ ]* 5.6 Write property test for chat error display
    - **Property 7: Chat Error Display**
    - **Validates: Requirements 3.5**

- [x] 6. Implement SSE manager for real-time updates
  - [x] 6.1 Integrate with existing AgentWeb.Streaming.SseManager
    - Leverage existing SSE infrastructure for workflow execution events
    - Use existing /api/agents/execute/stream endpoint for agent communication
    - Handle existing SSE event types (sse_token, sse_done, sse_error, sse_clarify)
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

  - [ ]* 6.2 Write property test for SSE integration
    - **Property 8: SSE Integration Management**
    - **Validates: Requirements 4.1, 4.2, 4.3, 4.4, 4.5**

  - [x] 6.3 Integrate SSE updates with workflow graph
    - Update graph node status based on agent execution progress
    - Map SSE events to workflow visualization updates
    - Display execution times and error information from SSE metadata
    - _Requirements: 2.2, 2.3, 2.4, 2.5_

  - [x] 6.4 Add SSE updates to chat interface
    - Show workflow progress in chat messages using existing streaming display
    - Display real-time execution status via AgentWebWeb.MessagesComponent
    - Handle SSE connection status in UI using existing patterns
    - _Requirements: 3.3, 4.5_

- [x] 7. Checkpoint - Ensure real-time functionality works
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Implement workflow validation infrastructure
  - [x] 8.1 Create WorkflowValidator module
    - Set up test database integration for isolation
    - Implement validation test execution framework using workflow-only approach
    - Add test result reporting and assertion handling
    - _Requirements: 6.1, 6.5_

  - [ ]* 8.2 Write property test for validation isolation
    - **Property 11: Workflow Validation Isolation**
    - **Validates: Requirements 6.1**

  - [x] 8.3 Implement Thanos context retention test
    - Create specific test scenario with "My name is Thanos" prompts
    - Add assertion logic for context retention validation using workflow execution
    - Implement test result analysis and reporting
    - _Requirements: 6.2, 6.3, 6.4_

  - [ ]* 8.4 Write unit test for Thanos scenario
    - Test specific "Thanos" context retention scenario
    - Validate response contains "Thanos" and is not clarification
    - _Requirements: 6.2, 6.3, 6.4_

- [x] 9. LM Studio integration (via existing provider system)
  - [x] 9.1 Verify LM Studio integration through provider system
    - Confirm existing OpenAI-compatible provider handles LM Studio connections
    - Validate multi-profile routing (execution, assessor, embeddings) to localhost:1234 endpoint
    - Test health check functionality for LM Studio availability detection
    - _Requirements: 7.1, 7.3, 7.4, 7.5_

  - [x]* 9.2 Write property test for LM Studio provider integration
    - **Property 13: LM Studio Integration via Provider System**
    - **Validates: Requirements 7.1, 7.3, 7.4, 7.5**

  - [x] 9.3 Verify LM Studio error handling through existing infrastructure
    - Confirm graceful handling of LM Studio unavailability via provider error handling
    - Validate clear error messages when connection fails
    - Test timeout handling and connection management
    - _Requirements: 7.2_

  - [x]* 9.4 Write property test for LM Studio unavailability handling
    - **Property 14: LM Studio Unavailability Handling**
    - **Validates: Requirements 7.2**

- [x] 10. Implement comprehensive error handling
  - [x] 10.1 Add global error handling patterns
    - Implement consistent error display across all components
    - Add error recovery strategies and user guidance
    - Ensure UI consistency with existing error patterns
    - _Requirements: 1.5, 8.4_

  - [ ]* 10.2 Write property test for error handling
    - **Property 3: Error Handling and Recovery**
    - **Validates: Requirements 1.5**

  - [x] 10.3 Add UI consistency validation
    - Ensure all components use existing design system
    - Validate responsive design patterns
    - Test component reuse and styling consistency
    - _Requirements: 8.1, 8.2, 8.3, 8.5_

  - [ ]* 10.4 Write property test for UI consistency
    - **Property 15: UI Component Consistency**
    - **Validates: Requirements 8.1, 8.2, 8.3, 8.4, 8.5**

- [x] 11. Integration and final wiring
  - [x] 11.1 Connect all components together
    - Wire agent selection to workflow graph and chat interface
    - Integrate SSE updates across all components
    - Connect validation system to testing interface
    - _Requirements: 1.1, 1.4_

  - [ ]* 11.2 Write integration tests
    - Test end-to-end agent testing workflows
    - Validate real-time SSE event delivery
    - Test complete user journey from agent selection to validation
    - _Requirements: 1.1, 1.4_

  - [x] 11.3 Add interface initialization property test
    - **Property 1: Agent Testing Interface Initialization**
    - **Validates: Requirements 1.2, 1.3**

- [ ] 12. Final checkpoint - Complete system validation
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation at key milestones
- Property tests validate universal correctness properties using StreamData
- Unit tests validate specific examples and edge cases
- Integration tests ensure end-to-end functionality works correctly
- **LM Studio integration (Task 9) is already complete** through the existing provider system - no additional implementation needed
- **Architecture Update**: System now uses workflow-only approach - plans have been phased out in favor of workflows for more reliable responses