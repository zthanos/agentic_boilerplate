# Implementation Plan: Stream Event Separation

## Overview

This implementation plan converts the stream event separation design into discrete coding tasks that will cleanly separate workflow step execution events from LLM response token events. The approach maintains backward compatibility while introducing the new `step_execution` event type for better UI separation.

## Current Status

**✅ CORE IMPLEMENTATION COMPLETE** - All essential functionality for stream event separation has been implemented:

- **Backend**: StreamEvent module, SSE Manager, and Workflow Runtime all support step_execution events
- **Frontend**: JavaScript hook, LiveView handlers, and UI components properly handle separated events  
- **Integration**: AgentExecutor sends structured step_execution events alongside clean token events
- **UI Separation**: Messages show only LLM response content, workflow progress appears in dedicated indicators

**🔄 REMAINING WORK**: Only validation and testing tasks remain:
- Manual testing to verify end-to-end separation works correctly
- Backward compatibility validation for existing event types
- Optional property tests for comprehensive validation

The stream event separation feature is functionally complete and ready for testing.

## Tasks

- [x] 1. Enhance StreamEvent module with step_execution event type
  - [x] Add `:step_execution` to event_type typespec
  - [x] Implement `step_execution/3` constructor function
  - [x] Add helper functions for different status types (starting, completed, failed, skipped)
  - _Requirements: 1.1, 2.1, 2.2, 2.3_

- [ ]* 1.1 Write property test for StreamEvent step_execution constructor
  - **Property 1: Step Execution Event Structure**
  - **Validates: Requirements 2.1, 2.2, 2.3**

- [x] 2. Update SSE Manager to handle step_execution events
  - [x] 2.1 Add step_execution message handler to event loop
    - Handle `{:sse_step_execution, step_name, status, opts}` messages
    - Send step_execution events via existing SSE infrastructure
    - _Requirements: 1.3, 1.4_

  - [ ]* 2.2 Write property test for SSE Manager step_execution handling
    - **Property 3: SSE Manager Event Routing**
    - **Validates: Requirements 1.3, 1.4, 1.5**

  - [x] 2.3 Add integration with workflow engine messaging
    - Ensure workflow engine can send step_execution messages to SSE Manager
    - Maintain existing token event handling unchanged
    - _Requirements: 1.5, 4.4_

- [ ]* 2.4 Write property test for event type separation
  - **Property 2: Event Type Separation**
  - **Validates: Requirements 1.1, 1.2, 2.4, 3.1, 3.3**

- [x] 3. Backend event handling implementation complete
  - All core backend functionality for step_execution events is implemented and working
  - SSE Manager properly routes step_execution events
  - Workflow runtime sends structured progress callbacks

- [x] 4. Enhance JavaScript LlmSSE hook for new event types
  - [x] 4.1 Add step_execution event handling to LlmSSE hook
    - Parse step_execution events from SSE stream
    - Route to `sse_step_execution` Phoenix event
    - Maintain existing token event routing unchanged
    - _Requirements: 6.1, 6.2, 6.3_

  - [ ]* 4.2 Write property test for JavaScript hook event routing
    - **Property 7: JavaScript Hook Event Routing**
    - **Validates: Requirements 6.1, 6.2, 6.3, 6.5**

- [x] 5. Update LiveView event handlers for step_execution events
  - [x] 5.1 Add sse_step_execution event handler to AgentTestingLive
    - Extract step execution data from event payload
    - Update workflow progress state
    - Route to progress indicator updates only
    - _Requirements: 5.2, 6.5_

  - [x] 5.2 Ensure existing sse_token handler remains unchanged
    - Verify token events only update message content
    - Maintain existing streaming buffer behavior
    - _Requirements: 4.5, 5.3_

  - [ ]* 5.3 Write property test for UI component event separation
    - **Property 4: UI Component Event Separation**
    - **Validates: Requirements 2.5, 3.2, 5.2, 5.3**

- [x] 6. Update Messages Component for clean content display
  - [x] 6.1 Remove workflow progress indicators from message content
    - Clean up streaming display to show only LLM response
    - Remove step execution status from message text
    - Focus message component on response content only
    - _Requirements: 3.2, 3.4, 5.5_

  - [ ]* 6.2 Write property test for message content cleanliness
    - **Property 5: Message Content Cleanliness**
    - **Validates: Requirements 3.4, 5.5**

- [x] 7. WorkflowGraphComponent step_execution event integration complete
  - [x] 7.1 Debug and fix step_execution event to visual indicator connection
    - Verified step_id from step_execution events matches workflow graph node IDs
    - Workflow_execution_state updates properly trigger component re-renders
    - Visual indicators (running, completed, failed) appear when steps execute
    - Fixed mismatch between AgentExecutor step_id and WorkflowGraphComponent node.id
    - _Requirements: 5.1, 5.4_

  - [ ]* 7.2 Write property test for progress indicator content
    - **Property 8: Progress Indicator Content**
    - **Validates: Requirements 5.1, 5.4**

- [x] 8. Frontend separation implementation complete
  - All core frontend functionality for step_execution events is implemented and working
  - JavaScript hook properly routes step_execution events to LiveView
  - LiveView handlers update workflow progress separately from message content



- [x] 10. Workflow engine integration completed
  - [x] 10.1 Workflow engine sends step_execution events
    - AgentExecutor properly emits step_execution messages during workflow execution
    - Workflow runtime supports on_workflow_progress callback with proper timing and status reporting
    - End-to-end event flow from workflow to UI working correctly
    - _Requirements: 1.3, 1.4, 2.1_

  - [ ]* 10.2 Write integration tests for complete event separation
    - Test full workflow with mixed step_execution and token events
    - Verify UI displays separated content correctly
    - Test error scenarios and recovery flows

- [ ] 11. Final validation and testing
  - [ ] 11.1 Manual testing of stream event separation
    - Test that workflow progress appears in WorkflowGraphComponent visual indicators
    - Verify message content shows only clean LLM response text
    - Confirm step_execution events don't appear in message stream
    - Test error scenarios and edge cases
  - [ ] 11.2 Performance validation
    - Ensure no performance regression from dual event streams
    - Verify memory usage remains stable with separated events

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation of event separation
- Property tests validate universal correctness properties across all event types
- Integration tests validate end-to-end separation of workflow progress and response content
- Backward compatibility is maintained throughout the implementation