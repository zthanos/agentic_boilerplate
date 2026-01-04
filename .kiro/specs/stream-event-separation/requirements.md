# Requirements Document

## Introduction

The current streaming event system mixes step execution status messages with actual LLM response tokens, causing confusion in the UI where users see both workflow progress updates and the final response content blended together. This feature will separate these concerns by introducing distinct event types for step execution vs. response content.

## Glossary

- **Stream_Event**: Event sent via SSE during agent execution
- **Step_Execution_Event**: Event indicating workflow step progress (starting, completed, failed)
- **Response_Token_Event**: Event containing actual LLM response content tokens
- **SSE_Manager**: Server-sent events manager handling streaming communication
- **Messages_Component**: UI component displaying chat messages and responses
- **Workflow_Progress**: Visual indicator showing step execution status separate from response content
- **LlmSSE_Hook**: JavaScript hook handling SSE events in the browser

## Requirements

### Requirement 1: Separate Event Types

**User Story:** As a developer, I want distinct event types for step execution and response content, so that the UI can handle them appropriately.

#### Acceptance Criteria

1. THE Stream_Event SHALL support a new event type called "step_execution" for workflow progress
2. THE Stream_Event SHALL maintain the existing "token" event type exclusively for LLM response content
3. WHEN a workflow step starts THEN the SSE_Manager SHALL send a "step_execution" event with status "starting"
4. WHEN a workflow step completes THEN the SSE_Manager SHALL send a "step_execution" event with status "completed"
5. WHEN LLM generates response tokens THEN the SSE_Manager SHALL send "token" events containing only the response content

### Requirement 2: Enhanced Step Execution Events

**User Story:** As a user, I want to see clear workflow progress separate from the response content, so that I can understand what the agent is doing.

#### Acceptance Criteria

1. WHEN a step_execution event is sent THEN it SHALL include step_name, status, and timestamp
2. WHEN a step completes THEN the step_execution event SHALL include execution_time_ms
3. WHEN a step fails THEN the step_execution event SHALL include error details
4. THE step_execution events SHALL NOT be mixed with response token content
5. THE Messages_Component SHALL display step execution progress separately from response content

### Requirement 3: Clean Response Token Handling

**User Story:** As a user, I want to see only the actual LLM response in the message content, so that I can focus on the answer without workflow noise.

#### Acceptance Criteria

1. THE token events SHALL contain only LLM-generated response content
2. WHEN streaming response tokens THEN the Messages_Component SHALL display only the response content
3. WHEN workflow steps execute THEN their status SHALL NOT appear in the response token stream
4. THE final assistant message SHALL contain only the clean LLM response text
5. THE workflow progress SHALL be displayed in a separate UI area from the message content

### Requirement 4: Backward Compatibility

**User Story:** As a developer, I want the changes to be backward compatible, so that existing functionality continues to work.

#### Acceptance Criteria

1. THE existing "token", "done", "error", and "clarify" event types SHALL remain unchanged
2. WHEN legacy clients receive events THEN they SHALL continue to function as before
3. THE new "step_execution" event type SHALL be additive to the existing event system
4. THE SSE_Manager SHALL maintain existing event handling patterns
5. THE existing event handlers SHALL continue to work without modification

### Requirement 5: UI Progress Separation

**User Story:** As a user, I want to see workflow progress in a dedicated area, so that it doesn't interfere with reading the response.

#### Acceptance Criteria

1. THE Messages_Component SHALL display workflow progress in a separate progress indicator
2. WHEN step_execution events are received THEN they SHALL update the progress indicator only
3. WHEN token events are received THEN they SHALL update the message content only
4. THE progress indicator SHALL show current step name, status, and completion percentage
5. THE message content area SHALL remain clean and focused on the LLM response

### Requirement 6: JavaScript Hook Integration

**User Story:** As a developer, I want the LlmSSE hook to handle the new event types, so that the frontend can properly route step execution vs. response events.

#### Acceptance Criteria

1. THE LlmSSE_Hook SHALL handle "step_execution" events separately from "token" events
2. WHEN a "step_execution" event is received THEN the LlmSSE_Hook SHALL trigger a "sse_step_execution" Phoenix event
3. WHEN a "token" event is received THEN the LlmSSE_Hook SHALL trigger the existing "sse_token" Phoenix event
4. THE LlmSSE_Hook SHALL maintain backward compatibility with existing event handling
5. THE step_execution events SHALL be routed to workflow progress updates, not message content