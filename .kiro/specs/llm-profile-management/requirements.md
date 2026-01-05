# Requirements Document

## Introduction

The LLM Profile Management system provides administrators with comprehensive tools to create, configure, and manage LLM (Large Language Model) profiles. Each profile defines the configuration parameters, generation settings, budget limits, and metadata for different AI models across various providers (OpenAI, Anthropic, Google, etc.).

## Glossary

- **LLM_Profile**: A configuration entity that defines all parameters needed to interact with a specific language model
- **Provider**: The service provider hosting the LLM (e.g., OpenAI, Anthropic, Google)
- **Generation_Parameters**: Settings that control how the model generates responses (temperature, top_p, etc.)
- **Budget_Limits**: Constraints on token usage and costs to prevent overuse
- **Auto_Tags**: System-generated tags based on provider, model type, and characteristics
- **Manual_Tags**: User-defined tags for custom categorization
- **Context_Module**: The business logic layer (AgentWeb.Llm) that handles profile operations
- **Store_Layer**: The data persistence layer (LLMProfileStore) that manages database operations
- **Admin_Interface**: The LiveView-based UI for profile management

## Requirements

### Requirement 1: Profile Creation and Management

**User Story:** As an administrator, I want to create and manage LLM profiles, so that I can configure different AI models for various use cases.

#### Acceptance Criteria

1. WHEN an administrator accesses the profile management interface, THE System SHALL display a list of existing profiles with their key information
2. WHEN an administrator clicks "Create Profile", THE System SHALL display a comprehensive form with all required and optional fields
3. WHEN an administrator fills out the profile form with valid data, THE System SHALL create a new LLMProfile struct and save it to the database
4. WHEN an administrator edits an existing profile, THE System SHALL pre-populate the form with current values and allow modifications
5. WHEN an administrator saves a profile, THE System SHALL validate all required fields are present and properly formatted

### Requirement 2: Automatic Tag Generation

**User Story:** As an administrator, I want the system to automatically generate relevant tags for profiles, so that profiles are properly categorized without manual effort.

#### Acceptance Criteria

1. WHEN a profile is created with a provider, THE System SHALL automatically add a provider-based tag (e.g., :openai, :anthropic)
2. WHEN a profile is created with a model name, THE System SHALL generate model-based tags (e.g., gpt-4 becomes :gpt4)
3. WHEN a model name contains "embed", THE System SHALL automatically add an :embeddings tag
4. WHEN a model name contains "chat", THE System SHALL automatically add a :chat tag
5. WHEN manual tags are provided by the user, THE System SHALL combine them with auto-generated tags without duplicates

### Requirement 3: Generation Parameters Configuration

**User Story:** As an administrator, I want to configure generation parameters for each profile, so that I can control how the model behaves for different use cases.

#### Acceptance Criteria

1. WHEN configuring generation parameters, THE System SHALL provide input fields for temperature (0.0-2.0)
2. WHEN configuring generation parameters, THE System SHALL provide input fields for top_p (0.0-1.0)
3. WHEN configuring generation parameters, THE System SHALL provide input fields for max_output_tokens with reasonable limits
4. WHEN configuring generation parameters, THE System SHALL provide input fields for presence_penalty (-2.0 to 2.0)
5. WHEN configuring generation parameters, THE System SHALL provide input fields for frequency_penalty (-2.0 to 2.0)
6. WHEN configuring generation parameters, THE System SHALL provide an optional seed field for reproducible outputs

### Requirement 4: Budget Limits Management

**User Story:** As an administrator, I want to set budget limits on profiles, so that I can control costs and prevent excessive usage.

#### Acceptance Criteria

1. WHEN setting budget limits, THE System SHALL provide optional fields for max_input_tokens
2. WHEN setting budget limits, THE System SHALL provide optional fields for max_output_tokens
3. WHEN setting budget limits, THE System SHALL provide optional fields for max_total_tokens
4. WHEN setting budget limits, THE System SHALL provide optional fields for max_cost_eur with decimal precision
5. WHEN setting budget limits, THE System SHALL provide optional fields for max_steps for multi-step operations

### Requirement 5: Tools and Configuration Management

**User Story:** As an administrator, I want to configure tools and advanced settings for profiles, so that I can customize model capabilities.

#### Acceptance Criteria

1. WHEN configuring tools, THE System SHALL accept a JSON array of tool names and validate the format
2. WHEN configuring stop sequences, THE System SHALL accept a JSON array of stop strings and validate the format
3. WHEN configuring tags, THE System SHALL accept comma-separated values and convert them to a proper list
4. WHEN configuring policy version, THE System SHALL default to "1" and make it read-only for now
5. WHEN configuring description, THE System SHALL provide a text area for optional profile documentation

### Requirement 6: Context Module Integration

**User Story:** As a system architect, I want proper separation between UI, business logic, and data layers, so that the system is maintainable and follows best practices.

#### Acceptance Criteria

1. WHEN the LiveView needs to create a profile, THE System SHALL call AgentWeb.Llm.create_profile/1
2. WHEN the LiveView needs to update a profile, THE System SHALL call AgentWeb.Llm.update_profile/2
3. WHEN the LiveView needs to list profiles, THE System SHALL call AgentWeb.Llm.list_profiles_ui/1
4. WHEN the context module processes data, THE System SHALL validate inputs before calling the store layer
5. WHEN the context module returns data to the UI, THE System SHALL convert it to UI-friendly format

### Requirement 7: Data Validation and Error Handling

**User Story:** As an administrator, I want clear validation and error messages, so that I can quickly identify and fix configuration issues.

#### Acceptance Criteria

1. WHEN required fields are missing, THE System SHALL display specific error messages indicating which fields are required
2. WHEN numeric values are out of range, THE System SHALL display validation errors with acceptable ranges
3. WHEN JSON fields contain invalid syntax, THE System SHALL display parsing error messages
4. WHEN provider values are invalid, THE System SHALL restrict selection to supported providers only
5. WHEN save operations fail, THE System SHALL display detailed error information to help troubleshooting

### Requirement 8: Profile Listing and Filtering

**User Story:** As an administrator, I want to view and filter profiles efficiently, so that I can manage large numbers of configurations.

#### Acceptance Criteria

1. WHEN viewing the profile list, THE System SHALL display key information including name, provider, model, and status
2. WHEN filtering by provider, THE System SHALL show only profiles matching the selected provider
3. WHEN filtering by status, THE System SHALL show only active or inactive profiles as selected
4. WHEN displaying profile statistics, THE System SHALL show counts by provider, status, and total profiles
5. WHEN profiles are updated, THE System SHALL refresh the list view automatically

### Requirement 9: Form Data Conversion and Persistence

**User Story:** As a system component, I want reliable data conversion between form inputs and domain objects, so that data integrity is maintained.

#### Acceptance Criteria

1. WHEN form data is submitted, THE System SHALL convert string inputs to appropriate data types (atoms, floats, integers)
2. WHEN JSON fields are processed, THE System SHALL parse valid JSON and provide defaults for invalid input
3. WHEN tags are processed, THE System SHALL split comma-separated strings and trim whitespace
4. WHEN the LLMProfile struct is created, THE System SHALL include all required fields with proper types
5. WHEN data is persisted, THE System SHALL use the LLMProfileStore.put/1 method for database operations

### Requirement 10: Provider Management

**User Story:** As an administrator, I want to select from supported providers, so that I can configure profiles for different AI services.

#### Acceptance Criteria

1. WHEN selecting a provider, THE System SHALL offer options for OpenAI, Anthropic, Google, Azure, and other supported providers
2. WHEN a provider is selected, THE System SHALL convert the string value to the appropriate atom for internal processing
3. WHEN displaying provider information, THE System SHALL show descriptive labels and helpful descriptions
4. WHEN validating providers, THE System SHALL ensure only supported provider atoms are accepted
5. WHEN new providers are added, THE System SHALL make them available in the selection dropdown