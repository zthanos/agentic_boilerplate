defmodule AgentCore.TestAssessment.ReportGenerator do
  @moduledoc """
  Module responsible for generating comprehensive assessment reports.
  """

  alias AgentCore.TestAssessment.{
    AssessmentReport,
    ReportSummary,
    TestCategory,
    RedundancyFinding,
    CoverageGap,
    ConfigIssue,
    Recommendation
  }

  @doc """
  Generates a comprehensive assessment report from analysis results.
  """
  @spec generate_report(map()) :: AssessmentReport.t()
  def generate_report(analysis_results) do
    summary = generate_summary(analysis_results)

    %AssessmentReport{
      summary: summary,
      test_categories: Map.get(analysis_results, :test_categories, %{}),
      redundancy_findings: Map.get(analysis_results, :redundancy_findings, []),
      coverage_gaps: Map.get(analysis_results, :coverage_gaps, []),
      config_issues: Map.get(analysis_results, :config_issues, []),
      recommendations: Map.get(analysis_results, :recommendations, []),
      phoenix_analysis: Map.get(analysis_results, :phoenix_analysis, %{}),
      generated_at: DateTime.utc_now()
    }
  end

  @doc """
  Organizes report by categories.
  """
  @spec organize_by_categories(AssessmentReport.t()) :: AssessmentReport.t()
  def organize_by_categories(report) do
    # Group test categories by primary type
    organized_categories =
      report.test_categories
      |> Enum.group_by(fn {_test_name, category} -> category.primary_type end)
      |> Map.new(fn {type, tests} ->
        {type, Map.new(tests)}
      end)

    # Sort recommendations by priority
    sorted_recommendations =
      report.recommendations
      |> Enum.sort_by(&priority_order/1)

    # Sort coverage gaps by priority
    sorted_coverage_gaps =
      report.coverage_gaps
      |> Enum.sort_by(&gap_priority_order/1)

    # Sort redundancy findings by confidence score (highest first)
    sorted_redundancy_findings =
      report.redundancy_findings
      |> Enum.sort_by(& &1.confidence_score, :desc)

    %{
      report
      | test_categories: organized_categories,
        recommendations: sorted_recommendations,
        coverage_gaps: sorted_coverage_gaps,
        redundancy_findings: sorted_redundancy_findings
    }
  end

  @doc """
  Exports report to different formats (text, JSON, HTML).
  """
  @spec export_report(AssessmentReport.t(), :text | :json | :html) :: String.t()
  def export_report(report, :text), do: export_text_format(report)
  def export_report(report, :json), do: export_json_format(report)
  def export_report(report, :html), do: export_html_format(report)

  # Private functions

  defp generate_summary(analysis_results) do
    redundancy_findings = Map.get(analysis_results, :redundancy_findings, [])
    coverage_gaps = Map.get(analysis_results, :coverage_gaps, [])
    config_issues = Map.get(analysis_results, :config_issues, [])
    parsed_tests = Map.get(analysis_results, :parsed_tests, [])
    test_files = Map.get(analysis_results, :test_files, [])
    apps_analyzed = Map.get(analysis_results, :apps_analyzed, 0)

    overall_score = calculate_overall_score(analysis_results)

    %ReportSummary{
      total_tests: length(parsed_tests),
      total_test_files: length(test_files),
      apps_analyzed: apps_analyzed,
      redundant_tests_found: length(redundancy_findings),
      coverage_gaps_found: length(coverage_gaps),
      config_issues_found: length(config_issues),
      overall_score: overall_score
    }
  end

  defp calculate_overall_score(analysis_results) do
    # Simple scoring algorithm based on issues found
    # Start with 100 and deduct points for issues
    base_score = 100.0

    redundancy_penalty = length(Map.get(analysis_results, :redundancy_findings, [])) * 2.0
    coverage_penalty = length(Map.get(analysis_results, :coverage_gaps, [])) * 1.5
    config_penalty = length(Map.get(analysis_results, :config_issues, [])) * 3.0

    total_penalty = redundancy_penalty + coverage_penalty + config_penalty

    max(0.0, base_score - total_penalty)
  end

  defp priority_order(%Recommendation{priority: :critical}), do: 1
  defp priority_order(%Recommendation{priority: :high}), do: 2
  defp priority_order(%Recommendation{priority: :medium}), do: 3
  defp priority_order(%Recommendation{priority: :low}), do: 4

  defp gap_priority_order(%CoverageGap{priority: :critical}), do: 1
  defp gap_priority_order(%CoverageGap{priority: :high}), do: 2
  defp gap_priority_order(%CoverageGap{priority: :medium}), do: 3
  defp gap_priority_order(%CoverageGap{priority: :low}), do: 4

  defp export_text_format(report) do
    """
    # Test Assessment Report
    Generated: #{DateTime.to_string(report.generated_at)}

    ## Summary
    #{format_summary_text(report.summary)}

    ## Test Categories
    #{format_categories_text(report.test_categories)}

    ## Redundancy Findings (#{length(report.redundancy_findings)})
    #{format_redundancy_findings_text(report.redundancy_findings)}

    ## Coverage Gaps (#{length(report.coverage_gaps)})
    #{format_coverage_gaps_text(report.coverage_gaps)}

    ## Configuration Issues (#{length(report.config_issues)})
    #{format_config_issues_text(report.config_issues)}

    ## Phoenix Analysis
    #{format_phoenix_analysis_text(report.phoenix_analysis)}

    ## Recommendations (#{length(report.recommendations)})
    #{format_recommendations_text(report.recommendations)}
    """
  end

  defp export_json_format(report) do
    report_map = %{
      summary: summary_to_map(report.summary),
      test_categories: categories_to_map(report.test_categories),
      redundancy_findings: Enum.map(report.redundancy_findings, &redundancy_finding_to_map/1),
      coverage_gaps: Enum.map(report.coverage_gaps, &coverage_gap_to_map/1),
      config_issues: Enum.map(report.config_issues, &config_issue_to_map/1),
      phoenix_analysis: phoenix_analysis_to_map(report.phoenix_analysis),
      recommendations: Enum.map(report.recommendations, &recommendation_to_map/1),
      generated_at: DateTime.to_iso8601(report.generated_at)
    }

    Jason.encode!(report_map, pretty: true)
  end

  defp export_html_format(report) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Test Assessment Report</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
            .header { border-bottom: 2px solid #333; padding-bottom: 20px; margin-bottom: 30px; }
            .section { margin-bottom: 30px; }
            .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 20px 0; }
            .summary-card { background: #f5f5f5; padding: 15px; border-radius: 5px; text-align: center; }
            .priority-critical { color: #d32f2f; font-weight: bold; }
            .priority-high { color: #f57c00; font-weight: bold; }
            .priority-medium { color: #1976d2; }
            .priority-low { color: #388e3c; }
            .finding { background: #f9f9f9; padding: 15px; margin: 10px 0; border-left: 4px solid #2196f3; }
            .justification { font-style: italic; color: #666; margin-top: 10px; }
        </style>
    </head>
    <body>
        <div class="header">
            <h1>Test Assessment Report</h1>
            <p>Generated: #{DateTime.to_string(report.generated_at)}</p>
        </div>

        <div class="section">
            <h2>Summary</h2>
            #{format_summary_html(report.summary)}
        </div>

        <div class="section">
            <h2>Test Categories</h2>
            #{format_categories_html(report.test_categories)}
        </div>

        <div class="section">
            <h2>Redundancy Findings (#{length(report.redundancy_findings)})</h2>
            #{format_redundancy_findings_html(report.redundancy_findings)}
        </div>

        <div class="section">
            <h2>Coverage Gaps (#{length(report.coverage_gaps)})</h2>
            #{format_coverage_gaps_html(report.coverage_gaps)}
        </div>

        <div class="section">
            <h2>Configuration Issues (#{length(report.config_issues)})</h2>
            #{format_config_issues_html(report.config_issues)}
        </div>

        <div class="section">
            <h2>Phoenix Analysis</h2>
            #{format_phoenix_analysis_html(report.phoenix_analysis)}
        </div>

        <div class="section">
            <h2>Recommendations (#{length(report.recommendations)})</h2>
            #{format_recommendations_html(report.recommendations)}
        </div>
    </body>
    </html>
    """
  end

  # Text formatting helpers
  defp format_summary_text(summary) do
    """
    - Total Tests: #{summary.total_tests}
    - Total Test Files: #{summary.total_test_files}
    - Apps Analyzed: #{summary.apps_analyzed}
    - Redundant Tests Found: #{summary.redundant_tests_found}
    - Coverage Gaps Found: #{summary.coverage_gaps_found}
    - Config Issues Found: #{summary.config_issues_found}
    - Overall Score: #{Float.round(summary.overall_score, 1)}/100
    """
  end

  defp format_categories_text(categories) when is_map(categories) do
    categories
    |> Enum.map(fn {type, tests} ->
      "### #{String.capitalize(to_string(type))} Tests (#{map_size(tests)})\n" <>
        (tests
         |> Enum.map(fn {test_name, _category} -> "- #{test_name}" end)
         |> Enum.join("\n"))
    end)
    |> Enum.join("\n\n")
  end

  defp format_redundancy_findings_text(findings) do
    findings
    |> Enum.with_index(1)
    |> Enum.map(fn {finding, index} ->
      """
      ### #{index}. #{Enum.join(finding.test_names, ", ")}
      Type: #{finding.redundancy_type}
      Confidence: #{Float.round(finding.confidence_score * 100, 1)}%
      Action: #{finding.recommended_action}
      Justification: #{finding.justification}
      """
    end)
    |> Enum.join("\n")
  end

  defp format_coverage_gaps_text(gaps) do
    gaps
    |> Enum.with_index(1)
    |> Enum.map(fn {gap, index} ->
      function_info = if gap.function_name, do: ".#{gap.function_name}", else: ""

      """
      ### #{index}. #{gap.module_name}#{function_info} [#{String.upcase(to_string(gap.priority))}]
      Type: #{gap.gap_type}
      Description: #{gap.description}
      Suggested Test Type: #{gap.suggested_test_type}
      """
    end)
    |> Enum.join("\n")
  end

  defp format_config_issues_text(issues) do
    issues
    |> Enum.with_index(1)
    |> Enum.map(fn {issue, index} ->
      """
      ### #{index}. #{issue.app_name} - #{issue.file_path} [#{String.upcase(to_string(issue.severity))}]
      Type: #{issue.issue_type}
      Description: #{issue.description}
      Suggested Fix: #{issue.suggested_fix}
      """
    end)
    |> Enum.join("\n")
  end

  defp format_recommendations_text(recommendations) do
    recommendations
    |> Enum.with_index(1)
    |> Enum.map(fn {rec, index} ->
      """
      ### #{index}. #{rec.title} [#{String.upcase(to_string(rec.priority))}]
      Type: #{rec.type}
      Effort: #{rec.estimated_effort}
      Description: #{rec.description}
      Affected Files: #{Enum.join(rec.affected_files, ", ")}
      Justification: #{rec.justification}
      """
    end)
    |> Enum.join("\n")
  end

  defp format_phoenix_analysis_text(phoenix_analysis) when is_map(phoenix_analysis) do
    liveview = Map.get(phoenix_analysis, :liveview_analysis, %{})
    form_validation = Map.get(phoenix_analysis, :form_validation_analysis, %{})
    component = Map.get(phoenix_analysis, :component_analysis, %{})
    property_test = Map.get(phoenix_analysis, :property_test_analysis, %{})
    overall_coverage = Map.get(phoenix_analysis, :overall_phoenix_coverage, 0.0)

    """
    ### Overall Phoenix Coverage: #{Float.round(overall_coverage, 1)}%

    ### LiveView Analysis
    - Tested Interactions: #{length(Map.get(liveview, :tested_interactions, []))}
    - Untested Interactions: #{length(Map.get(liveview, :untested_interactions, []))}
    - Interaction Coverage: #{Float.round(Map.get(liveview, :interaction_coverage, 0.0), 1)}%

    ### Form Validation Analysis
    - Tested Validations: #{length(Map.get(form_validation, :tested_validations, []))}
    - Untested Validations: #{length(Map.get(form_validation, :untested_validations, []))}
    - Validation Coverage: #{Float.round(Map.get(form_validation, :validation_coverage, 0.0), 1)}%

    ### Component Analysis
    - Tested Components: #{length(Map.get(component, :tested_components, []))}
    - Untested Components: #{length(Map.get(component, :untested_components, []))}
    - Component Coverage: #{Float.round(Map.get(component, :component_coverage, 0.0), 1)}%

    ### Property-Based Test Opportunities
    - Parser Opportunities: #{length(Map.get(property_test, :parser_opportunities, []))}
    - Transformation Opportunities: #{length(Map.get(property_test, :transformation_opportunities, []))}
    - Existing Property Tests: #{length(Map.get(property_test, :existing_property_tests, []))}
    """
  end

  defp format_phoenix_analysis_text(_), do: "No Phoenix analysis data available."

  # HTML formatting helpers
  defp format_summary_html(summary) do
    """
    <div class="summary-grid">
        <div class="summary-card">
            <h3>#{summary.total_tests}</h3>
            <p>Total Tests</p>
        </div>
        <div class="summary-card">
            <h3>#{summary.total_test_files}</h3>
            <p>Test Files</p>
        </div>
        <div class="summary-card">
            <h3>#{summary.apps_analyzed}</h3>
            <p>Apps Analyzed</p>
        </div>
        <div class="summary-card">
            <h3>#{summary.redundant_tests_found}</h3>
            <p>Redundant Tests</p>
        </div>
        <div class="summary-card">
            <h3>#{summary.coverage_gaps_found}</h3>
            <p>Coverage Gaps</p>
        </div>
        <div class="summary-card">
            <h3>#{summary.config_issues_found}</h3>
            <p>Config Issues</p>
        </div>
        <div class="summary-card">
            <h3>#{Float.round(summary.overall_score, 1)}/100</h3>
            <p>Overall Score</p>
        </div>
    </div>
    """
  end

  defp format_categories_html(categories) when is_map(categories) do
    categories
    |> Enum.map(fn {type, tests} ->
      test_list =
        tests
        |> Enum.map(fn {test_name, _category} -> "<li>#{test_name}</li>" end)
        |> Enum.join("")

      """
      <h3>#{String.capitalize(to_string(type))} Tests (#{map_size(tests)})</h3>
      <ul>#{test_list}</ul>
      """
    end)
    |> Enum.join("")
  end

  defp format_redundancy_findings_html(findings) do
    findings
    |> Enum.with_index(1)
    |> Enum.map(fn {finding, index} ->
      """
      <div class="finding">
          <h4>#{index}. #{Enum.join(finding.test_names, ", ")}</h4>
          <p><strong>Type:</strong> #{finding.redundancy_type}</p>
          <p><strong>Confidence:</strong> #{Float.round(finding.confidence_score * 100, 1)}%</p>
          <p><strong>Action:</strong> #{finding.recommended_action}</p>
          <div class="justification">#{finding.justification}</div>
      </div>
      """
    end)
    |> Enum.join("")
  end

  defp format_coverage_gaps_html(gaps) do
    gaps
    |> Enum.with_index(1)
    |> Enum.map(fn {gap, index} ->
      function_info = if gap.function_name, do: ".#{gap.function_name}", else: ""
      priority_class = "priority-#{gap.priority}"

      """
      <div class="finding">
          <h4 class="#{priority_class}">#{index}. #{gap.module_name}#{function_info}</h4>
          <p><strong>Type:</strong> #{gap.gap_type}</p>
          <p><strong>Priority:</strong> <span class="#{priority_class}">#{String.upcase(to_string(gap.priority))}</span></p>
          <p><strong>Description:</strong> #{gap.description}</p>
          <p><strong>Suggested Test Type:</strong> #{gap.suggested_test_type}</p>
      </div>
      """
    end)
    |> Enum.join("")
  end

  defp format_config_issues_html(issues) do
    issues
    |> Enum.with_index(1)
    |> Enum.map(fn {issue, index} ->
      severity_class = "priority-#{issue.severity}"

      """
      <div class="finding">
          <h4 class="#{severity_class}">#{index}. #{issue.app_name} - #{issue.file_path}</h4>
          <p><strong>Type:</strong> #{issue.issue_type}</p>
          <p><strong>Severity:</strong> <span class="#{severity_class}">#{String.upcase(to_string(issue.severity))}</span></p>
          <p><strong>Description:</strong> #{issue.description}</p>
          <p><strong>Suggested Fix:</strong> #{issue.suggested_fix}</p>
      </div>
      """
    end)
    |> Enum.join("")
  end

  defp format_recommendations_html(recommendations) do
    recommendations
    |> Enum.with_index(1)
    |> Enum.map(fn {rec, index} ->
      priority_class = "priority-#{rec.priority}"

      """
      <div class="finding">
          <h4 class="#{priority_class}">#{index}. #{rec.title}</h4>
          <p><strong>Type:</strong> #{rec.type}</p>
          <p><strong>Priority:</strong> <span class="#{priority_class}">#{String.upcase(to_string(rec.priority))}</span></p>
          <p><strong>Effort:</strong> #{rec.estimated_effort}</p>
          <p><strong>Description:</strong> #{rec.description}</p>
          <p><strong>Affected Files:</strong> #{Enum.join(rec.affected_files, ", ")}</p>
          <div class="justification">#{rec.justification}</div>
      </div>
      """
    end)
    |> Enum.join("")
  end

  defp format_phoenix_analysis_html(phoenix_analysis) when is_map(phoenix_analysis) do
    liveview = Map.get(phoenix_analysis, :liveview_analysis, %{})
    form_validation = Map.get(phoenix_analysis, :form_validation_analysis, %{})
    component = Map.get(phoenix_analysis, :component_analysis, %{})
    property_test = Map.get(phoenix_analysis, :property_test_analysis, %{})
    overall_coverage = Map.get(phoenix_analysis, :overall_phoenix_coverage, 0.0)

    """
    <div class="summary-grid">
        <div class="summary-card">
            <h3>#{Float.round(overall_coverage, 1)}%</h3>
            <p>Overall Phoenix Coverage</p>
        </div>
        <div class="summary-card">
            <h3>#{Float.round(Map.get(liveview, :interaction_coverage, 0.0), 1)}%</h3>
            <p>LiveView Coverage</p>
        </div>
        <div class="summary-card">
            <h3>#{Float.round(Map.get(form_validation, :validation_coverage, 0.0), 1)}%</h3>
            <p>Validation Coverage</p>
        </div>
        <div class="summary-card">
            <h3>#{Float.round(Map.get(component, :component_coverage, 0.0), 1)}%</h3>
            <p>Component Coverage</p>
        </div>
    </div>

    <h3>LiveView Analysis</h3>
    <p><strong>Tested Interactions:</strong> #{length(Map.get(liveview, :tested_interactions, []))}</p>
    <p><strong>Untested Interactions:</strong> #{length(Map.get(liveview, :untested_interactions, []))}</p>

    <h3>Form Validation Analysis</h3>
    <p><strong>Tested Validations:</strong> #{length(Map.get(form_validation, :tested_validations, []))}</p>
    <p><strong>Untested Validations:</strong> #{length(Map.get(form_validation, :untested_validations, []))}</p>

    <h3>Component Analysis</h3>
    <p><strong>Tested Components:</strong> #{length(Map.get(component, :tested_components, []))}</p>
    <p><strong>Untested Components:</strong> #{length(Map.get(component, :untested_components, []))}</p>

    <h3>Property-Based Test Opportunities</h3>
    <p><strong>Parser Opportunities:</strong> #{length(Map.get(property_test, :parser_opportunities, []))}</p>
    <p><strong>Transformation Opportunities:</strong> #{length(Map.get(property_test, :transformation_opportunities, []))}</p>
    <p><strong>Existing Property Tests:</strong> #{length(Map.get(property_test, :existing_property_tests, []))}</p>
    """
  end

  defp format_phoenix_analysis_html(_), do: "<p>No Phoenix analysis data available.</p>"

  # JSON conversion helpers
  defp summary_to_map(summary) do
    %{
      total_tests: summary.total_tests,
      total_test_files: summary.total_test_files,
      apps_analyzed: summary.apps_analyzed,
      redundant_tests_found: summary.redundant_tests_found,
      coverage_gaps_found: summary.coverage_gaps_found,
      config_issues_found: summary.config_issues_found,
      overall_score: summary.overall_score
    }
  end

  defp categories_to_map(categories) when is_map(categories) do
    categories
    |> Map.new(fn {type, tests} ->
      {type,
       Map.new(tests, fn {test_name, category} ->
         {test_name, category_to_map(category)}
       end)}
    end)
  end

  defp category_to_map(category) do
    %{
      primary_type: category.primary_type,
      secondary_types: category.secondary_types,
      confidence_scores: category.confidence_scores,
      focus_areas: category.focus_areas
    }
  end

  defp redundancy_finding_to_map(finding) do
    %{
      test_names: finding.test_names,
      redundancy_type: finding.redundancy_type,
      confidence_score: finding.confidence_score,
      recommended_action: finding.recommended_action,
      justification: finding.justification
    }
  end

  defp coverage_gap_to_map(gap) do
    %{
      module_name: gap.module_name,
      function_name: gap.function_name,
      gap_type: gap.gap_type,
      priority: gap.priority,
      description: gap.description,
      suggested_test_type: gap.suggested_test_type
    }
  end

  defp config_issue_to_map(issue) do
    %{
      app_name: issue.app_name,
      file_path: issue.file_path,
      issue_type: issue.issue_type,
      severity: issue.severity,
      description: issue.description,
      suggested_fix: issue.suggested_fix
    }
  end

  defp recommendation_to_map(rec) do
    %{
      type: rec.type,
      priority: rec.priority,
      title: rec.title,
      description: rec.description,
      affected_files: rec.affected_files,
      estimated_effort: rec.estimated_effort,
      justification: rec.justification
    }
  end

  defp phoenix_analysis_to_map(phoenix_analysis) when is_map(phoenix_analysis) do
    phoenix_analysis
  end

  defp phoenix_analysis_to_map(_), do: %{}
end
