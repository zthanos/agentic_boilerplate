# Implementation Plan

- [x] 1. Set up core workflow engine foundation





  - Create directory structure for workflow engine modules
  - Define core behavior modules and structs
  - Set up testing framework with StreamData for property-based testing
  - _Requirements: 1.1, 2.1, 2.2_

- [x] 1.1 Create WorkflowEngine.Step behavior module


  - Define Step behavior with id/0 and run/3 callbacks
  - Create documentation and examples for step implementations
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [ ]* 1.2 Write property test for Step behavior interface compliance
  - **Property 5: Step behavior interface compliance**
  - **Validates: Requirements 2.1, 2.2, 2.3, 2.4**

- [x] 1.3 Create WorkflowEngine.Spec struct and validation


  - Implement Spec struct with all required fields
  - Create validation functions for workflow specifications
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [ ]* 1.4 Write property test for workflow specification validation
  - **Property 1: Workflow specification validation**
  - **Validates: Requirements 1.1, 7.1, 7.2, 7.3**

- [ ]* 1.5 Write property test for workflow specification structure
  - **Property 7: Workflow specification structure**
  - **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**

- [x] 2. Implement runtime context and execution engine




  - Create WorkflowEngine.Context struct for state management
  - Implement WorkflowEngine.Runtime execution engine
  - Add comprehensive error handling and tracing
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

- [x] 2.1 Create WorkflowEngine.Context struct

  - Implement Context struct with decisions, artifacts, debug, meta, events maps
  - Create helper functions for context manipulation
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

- [ ]* 2.2 Write property test for context data organization
  - **Property 6: Context data organization**
  - **Validates: Requirements 4.1, 4.2, 4.3, 4.4, 4.5**

- [x] 2.3 Implement WorkflowEngine.Runtime execution engine


  - Create main execution loop with node traversal
  - Implement edge predicate evaluation
  - Add deterministic edge resolution logic
  - _Requirements: 1.2, 1.5, 1.6_

- [ ]* 2.4 Write property test for deterministic execution flow
  - **Property 2: Deterministic execution flow**
  - **Validates: Requirements 1.2, 1.5**

- [x] 2.5 Implement comprehensive error handling


  - Add error capture and propagation logic
  - Create WorkflowResult struct for execution results
  - Implement fail-fast error semantics
  - _Requirements: 1.3, 1.6, 6.5_

- [ ]* 2.6 Write property test for error handling completeness
  - **Property 3: Error handling completeness**
  - **Validates: Requirements 1.3, 1.6, 6.5, 8.5**

- [x] 2.7 Add execution tracing and observability


  - Implement detailed execution tracing
  - Create trace entry structures
  - Add performance timing and metadata capture
  - _Requirements: 6.1, 6.2, 6.3, 6.4_

- [ ]* 2.8 Write property test for execution tracing completeness
  - **Property 8: Execution tracing completeness**
  - **Validates: Requirements 6.1, 6.2, 6.3**

- [ ]* 2.9 Write property test for successful completion consistency
  - **Property 4: Successful completion consistency**
  - **Validates: Requirements 1.4, 6.4**

- [x] 3. Checkpoint - Ensure all core engine tests pass

  - Ensure all tests pass, ask the user if questions arise


- [x] 4. Create workflow registry and management system


  - Implement WorkflowEngine.Registry for workflow storage
  - Add workflow validation and compilation features
  - Create workflow builder utilities
  - _Requirements: 7.1, 7.2, 7.3, 7.5_


- [x] 4.1 Implement WorkflowEngine.Registry module

  - Create registry for storing and managing workflow specifications
  - Add workflow registration and retrieval functions
  - Implement workflow validation pipeline
  - _Requirements: 7.1, 7.2, 7.3_

- [ ]* 4.2 Write unit tests for workflow registry operations
  - Test workflow registration and retrieval
  - Test validation error handling
  - Test registry state management
  - _Requirements: 7.1, 7.2, 7.3_

- [x] 4.3 Add workflow compilation and optimization


  - Implement optional execution plan generation
  - Create workflow optimization utilities
  - Add performance analysis tools
  - _Requirements: 7.5_

- [ ]* 4.4 Write unit tests for workflow compilation
  - Test execution plan generation
  - Test optimization correctness
  - Test compilation error handling
  - _Requirements: 7.5_

- [x] 5. Implement comprehensive History RAG Augmentation workflow steps
  - Create all six step implementations for complete RAG workflow
  - Implement workflow specification with full routing logic
  - Add helper functions and utilities for vector search and context composition
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7_

- [x] 5.1 Create HistoryWorkflow.AssessNeedStep
  - Implement step to evaluate if historical context retrieval is needed
  - Add decision logic based on message content, conversation state, and context
  - Create output format for needs_history decision with reasoning
  - _Requirements: 5.1_

- [x] 5.2 Create HistoryWorkflow.BuildQueryStep
  - Implement structured query generation from current message and conversation context
  - Add semantic keyword extraction and conversation filtering logic
  - Create optimized query parameters for vector database search
  - _Requirements: 5.2_

- [x] 5.3 Create HistoryWorkflow.RetrieveCandidatesStep
  - Implement vector similarity search integration with conversation history
  - Add semantic similarity scoring and initial candidate ranking
  - Handle empty result cases and search optimization
  - _Requirements: 5.3_

- [x] 5.4 Create HistoryWorkflow.RerankCandidatesStep
  - Implement advanced candidate reranking with relevance scoring algorithms
  - Add context quality assessment and candidate refinement
  - Create top candidates selection with quality thresholds
  - _Requirements: 5.4_

- [x] 5.5 Create HistoryWorkflow.ComposeContextStep
  - Implement intelligent context string formatting and prompt augmentation
  - Add historical item integration with conversation flow preservation
  - Handle context composition with metadata and usage tracking
  - _Requirements: 5.5_

- [x] 5.6 Create HistoryWorkflow.DoneStep
  - Implement workflow finalization with complete augmented prompt generation
  - Create comprehensive output formatting with context and metadata
  - Add result validation and usage statistics
  - _Requirements: 5.6, 5.7_

- [ ]* 5.7 Write property test for comprehensive history workflow behavior
  - **Property 9: Complete History workflow behavior**
  - **Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7**

- [x] 5.8 Create comprehensive history workflow specification
  - Define complete workflow spec with all six nodes and comprehensive edge routing
  - Add sophisticated predicate functions for intelligent workflow routing
  - Register workflow in registry with full step integration
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7_

- [ ]* 5.9 Write comprehensive integration tests for history workflow
  - Test complete end-to-end workflow execution with all steps
  - Test various input scenarios including first messages, empty conversations, and rich context
  - Test error handling and edge cases across the entire workflow pipeline
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7_

- [x] 6. Implement agent interface layer for workflow exposure
  - Create agent system that exposes workflows to UI controllers
  - Add workflow selection and routing logic within agents
  - Implement LLM integration capabilities through agent interface
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 9.1, 9.2, 9.3, 9.4, 9.5_

- [x] 6.1 Create WorkflowEngine.Agent module
  - Implement agent system that can expose one or more workflows
  - Add workflow selection logic based on request parameters
  - Create clean interface for UI controller interaction
  - _Requirements: 8.1, 8.2, 8.4, 9.1, 9.2_

- [x] 6.2 Implement agent-to-LLM integration layer
  - Create LLM integration capabilities within agent system
  - Add workflow result formatting for LLM consumption
  - Implement clean separation between agent management and LLM integration
  - _Requirements: 8.3, 8.5, 9.1, 9.3, 9.4_

- [ ]* 6.3 Write property test for agent-based workflow execution
  - **Property 10: Agent-based workflow execution**
  - **Validates: Requirements 8.1, 8.2, 8.3, 8.4, 8.5**

- [ ]* 6.4 Write property test for clean architectural separation
  - **Property 11: Clean architectural separation**
  - **Validates: Requirements 9.1, 9.2, 9.3, 9.4, 9.5**

- [ ]* 6.5 Write integration tests for agent-controller-LLM integration
  - Test UI controller interaction with agents for workflow execution
  - Test agent workflow selection and routing logic
  - Test LLM integration through agent interface with proper error handling
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 9.1, 9.2, 9.3, 9.4, 9.5_

- [x] 7. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise

- [-] 8. Implement RAG-enhanced conversation workflow for complete conversational AI processing
  - Create comprehensive conversation workflow that uses LLM query generation, vector retrieval, prompt enhancement, and clarification assessment
  - Implement workflow specification with intelligent routing between response generation and clarification collection
  - Add integration with existing vector database and LLM infrastructure without plan system dependencies
  - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 10.7, 11.1, 11.2, 11.3, 11.4, 11.5_

- [x] 8.1 Create RagConversationWorkflow.GenerateQueryStep
  - Implement LLM-based query generation from user messages for vector database search
  - Add structured query formatting optimized for conversation history retrieval
  - Create fallback logic for cases where LLM query generation fails
  - _Requirements: 10.1, 11.1_

- [x] 8.2 Create RagConversationWorkflow.RetrieveContextStep
  - Implement vector database integration for retrieving relevant conversation history
  - Add semantic similarity scoring and context ranking logic
  - Handle empty results and search optimization without plan system dependencies
  - _Requirements: 10.2, 11.2_

- [x] 8.3 Create RagConversationWorkflow.EnhancePromptStep
  - Implement intelligent prompt augmentation with retrieved historical context
  - Add structured context formatting that preserves conversation flow
  - Create workflow-specific prompt enhancement without reusing plan formatting utilities
  - _Requirements: 10.3, 11.3_

- [x] 8.4 Create RagConversationWorkflow.AssessClarificationStep
  - Implement LLM-based clarification need assessment for enhanced prompts
  - Add decision logic for routing between direct response and clarification collection
  - Create workflow-specific clarification logic independent of plan system clarification modules
  - _Requirements: 10.4, 11.4_

- [x] 8.5 Create RagConversationWorkflow.FinalResponseStep
  - Implement final LLM response generation using enhanced prompts
  - Add response formatting and metadata collection for conversation completion
  - Handle response generation errors with workflow-specific error handling
  - _Requirements: 10.5, 11.5_

- [x] 8.6 Create RagConversationWorkflow.CollectClarificationStep
  - Implement clarification question presentation and user interaction handling
  - Add clarification collection logic with proper user interface integration
  - Create clarification workflow completion with enhanced prompt regeneration
  - _Requirements: 10.6, 11.5_

- [ ]* 8.7 Write property test for RAG-enhanced conversation workflow behavior
  - **Property 10: RAG-enhanced conversation workflow behavior**
  - **Validates: Requirements 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 10.7**

- [ ]* 8.8 Write property test for workflow infrastructure independence
  - **Property 11: Workflow infrastructure independence**
  - **Validates: Requirements 11.1, 11.2, 11.3, 11.4, 11.5**

- [x] 8.9 Create comprehensive RAG conversation workflow specification
  - Define complete workflow spec with all six nodes and intelligent routing logic
  - Add sophisticated predicate functions for conversation flow management
  - Register workflow in registry with full step integration and proper error handling
  - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 10.7_

- [ ]* 8.10 Write comprehensive integration tests for RAG conversation workflow
  - Test complete end-to-end conversation processing with all workflow steps
  - Test various conversation scenarios including clarification needs and direct responses
  - Test error handling and edge cases across the entire conversation pipeline
  - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 10.7, 11.1, 11.2, 11.3, 11.4, 11.5_

- [ ] 9. Update existing AssessNeedStep to follow RAG conversation workflow pattern
  - Modify existing HistoryWorkflow.AssessNeedStep to use LLM query generation approach
  - Update step logic to match the pattern established in AssessNeedForHistoryStep but within workflow context
  - Ensure proper integration with workflow engine context and error handling
  - _Requirements: 10.1, 11.1, 11.5_

- [ ] 9.1 Refactor AssessNeedStep implementation
  - Update step to use LLM for generating structured queries instead of simple boolean assessment
  - Add proper query generation logic following the pattern from plan system but adapted for workflow context
  - Maintain workflow engine context handling and decision storage patterns
  - _Requirements: 10.1, 11.1_

- [ ]* 9.2 Write unit tests for updated AssessNeedStep
  - Test LLM query generation functionality with various user message inputs
  - Test error handling and fallback behavior when LLM calls fail
  - Test proper workflow context integration and decision storage
  - _Requirements: 10.1, 11.1, 11.5_

- [ ] 10. Final integration checkpoint - Ensure all workflow tests pass
  - Ensure all workflow engine tests pass including new RAG conversation workflow
  - Verify proper integration between existing history workflow and new conversation workflow
  - Ask the user if questions arise regarding workflow implementation

- [ ] 11. Implement real-time workflow graph progress visualization
  - Add structured progress events for workflow step execution status
  - Update SSE Manager to handle workflow progress events in addition to token events
  - Update LiveView to process workflow progress events and update graph state in real-time
  - _Requirements: 12.1, 12.2, 12.3, 12.4_

- [ ] 11.1 Add structured workflow progress events to runtime
  - Modify WorkflowEngine.Runtime to send structured step progress events
  - Create WorkflowProgressEvent struct for step status updates (start, complete, error)
  - Integrate progress events with existing streaming callback system
  - _Requirements: 12.1_

- [ ] 11.2 Update SSE Manager for workflow progress events
  - Extend SseManager to handle workflow progress events as separate event type
  - Add new SSE event types: workflow_step_start, workflow_step_complete, workflow_step_error
  - Ensure workflow progress events are sent alongside token streaming events
  - _Requirements: 12.2_

- [ ] 11.3 Update JavaScript SSE hook for workflow progress
  - Extend LlmSSE hook to parse and handle workflow progress events
  - Add event handlers for workflow_step_start, workflow_step_complete, workflow_step_error
  - Send workflow progress events to LiveView for graph state updates
  - _Requirements: 12.3_

- [ ] 11.4 Update LiveView for real-time workflow graph updates
  - Add workflow progress event handlers to AgentTestingLive
  - Update workflow_execution_state assign based on step progress events
  - Ensure WorkflowGraphComponent receives real-time execution state updates
  - _Requirements: 12.4_

- [ ]* 11.5 Write integration tests for workflow graph progress visualization
  - Test end-to-end workflow progress from runtime to UI graph updates
  - Test step status transitions (pending → running → completed/failed)
  - Test real-time graph visualization updates during workflow execution
  - _Requirements: 12.1, 12.2, 12.3, 12.4_

- [ ] 12. Final checkpoint - Ensure workflow graph progress visualization works
  - Test complete workflow execution with real-time graph updates
  - Verify step progress is visible in both chat messages and graph visualization
  - Ask the user if questions arise regarding workflow graph implementation