# TestAssessmentApp

TestAssessmentApp provides comprehensive test suite analysis and optimization capabilities for Phoenix umbrella projects.

## Features

- **Test Discovery**: Automatically discover and analyze test files across umbrella apps
- **Coverage Analysis**: Analyze test coverage and identify gaps
- **Redundancy Detection**: Find and eliminate redundant tests
- **Categorization**: Classify tests by type (unit, integration, property-based, etc.)
- **Optimization**: Automated test suite optimization and reorganization
- **Reporting**: Generate comprehensive assessment reports with actionable recommendations

## Usage

### Command Line Interface

```bash
# Run assessment on current umbrella project
mix test_assessment

# Run assessment on specific path
mix test_assessment --path /path/to/umbrella/project

# Generate optimized test suite
mix test_assessment --optimize

# Generate report in specific format
mix test_assessment --format json
```

### Programmatic API

```elixir
# Assess test suite
{:ok, report} = TestAssessmentApp.assess_test_suite("/path/to/umbrella")

# Validate umbrella project
{:ok, app_paths} = TestAssessmentApp.validate_umbrella_project("/path/to/umbrella")
```

## Architecture

TestAssessmentApp follows clean architecture principles with clear separation between:

- **Domain Models**: Core data structures and business logic
- **Analysis Engines**: Test parsing, coverage analysis, and categorization
- **Optimization**: Test suite optimization and reorganization
- **Reporting**: Report generation and formatting
- **CLI**: Command-line interface and Mix tasks