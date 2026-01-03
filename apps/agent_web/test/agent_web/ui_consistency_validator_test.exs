defmodule AgentWeb.UIConsistencyValidatorTest do
  use ExUnit.Case, async: true
  alias AgentWeb.UIConsistencyValidator

  describe "validate_component/2" do
    test "validates proper DaisyUI component usage" do
      valid_content = """
      <div class="card bg-base-200 shadow-xl">
        <div class="card-body">
          <button class="btn btn-primary">Click me</button>
          <div class="alert alert-info">Info message</div>
        </div>
      </div>
      """

      assert {:ok, :valid} =
               UIConsistencyValidator.validate_component(valid_content, "TestComponent")
    end

    test "detects improper color usage" do
      invalid_content = """
      <div class="bg-red-500 text-red-700">
        <button class="bg-blue-500">Click me</button>
      </div>
      """

      assert {:error, violations} =
               UIConsistencyValidator.validate_component(invalid_content, "TestComponent")

      assert Enum.any?(violations, &String.contains?(&1, "semantic colors"))
    end

    test "detects missing accessibility attributes" do
      invalid_content = """
      <button>Click me</button>
      <img src="test.jpg">
      <input type="text">
      """

      assert {:error, violations} =
               UIConsistencyValidator.validate_component(invalid_content, "TestComponent")

      assert Enum.any?(violations, &String.contains?(&1, "aria-label"))
      assert Enum.any?(violations, &String.contains?(&1, "alt attributes"))
      assert Enum.any?(violations, &String.contains?(&1, "properly labeled"))
    end

    test "validates responsive design patterns" do
      responsive_content = """
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 px-4 sm:px-6 lg:px-8">
        <div class="card">Content</div>
      </div>
      """

      assert {:ok, :valid} =
               UIConsistencyValidator.validate_component(responsive_content, "TestComponent")
    end

    test "detects improper heading hierarchy" do
      invalid_content = """
      <h1>Title</h1>
      <h3>Subtitle</h3>
      <h2>Section</h2>
      """

      assert {:error, violations} =
               UIConsistencyValidator.validate_component(invalid_content, "TestComponent")

      assert Enum.any?(violations, &String.contains?(&1, "heading hierarchy"))
    end

    test "validates proper heading hierarchy" do
      valid_content = """
      <h1>Title</h1>
      <h2>Section</h2>
      <h3>Subsection</h3>
      """

      assert {:ok, :valid} =
               UIConsistencyValidator.validate_component(valid_content, "TestComponent")
    end
  end

  describe "validate_agent_testing_interface/0" do
    test "validates all agent testing components exist and are readable" do
      # This test ensures the validator can read the actual component files
      result = UIConsistencyValidator.validate_agent_testing_interface()

      # Should return either :all_valid or a list of specific violations
      case result do
        {:ok, :all_valid} ->
          assert true

        {:error, invalid_components} ->
          # If there are violations, they should be properly formatted
          assert is_list(invalid_components)

          Enum.each(invalid_components, fn {name, status, violations} ->
            assert is_binary(name)
            assert status in [:invalid, :error]
            assert is_list(violations)
          end)
      end
    end
  end

  describe "validate_agent_testing_patterns/0" do
    test "validates specific UI patterns used in agent testing" do
      result = UIConsistencyValidator.validate_agent_testing_patterns()

      case result do
        {:ok, message} ->
          assert is_binary(message)

        {:error, issues} ->
          assert is_list(issues)

          Enum.each(issues, fn issue ->
            assert is_binary(issue)
          end)
      end
    end
  end

  describe "generate_consistency_report/0" do
    test "generates a comprehensive UI consistency report" do
      report = UIConsistencyValidator.generate_consistency_report()

      assert is_binary(report)
      assert String.contains?(report, "UI Consistency Report")

      # Report should contain either success or violation information
      assert String.contains?(report, "✅") or String.contains?(report, "❌")
    end
  end

  describe "design system compliance" do
    test "validates DaisyUI card patterns" do
      valid_card = """
      <div class="card bg-base-200 shadow-xl">
        <div class="card-body">
          <h2 class="card-title">Title</h2>
          <p>Content</p>
          <div class="card-actions justify-end">
            <button class="btn btn-primary">Action</button>
          </div>
        </div>
      </div>
      """

      assert {:ok, :valid} = UIConsistencyValidator.validate_component(valid_card, "CardTest")
    end

    test "validates DaisyUI button patterns" do
      valid_buttons = """
      <button class="btn btn-primary">Primary</button>
      <button class="btn btn-secondary">Secondary</button>
      <button class="btn btn-ghost">Ghost</button>
      <button class="btn btn-outline">Outline</button>
      """

      assert {:ok, :valid} =
               UIConsistencyValidator.validate_component(valid_buttons, "ButtonTest")
    end

    test "validates DaisyUI alert patterns" do
      valid_alerts = """
      <div class="alert alert-info">
        <div>Info message</div>
      </div>
      <div class="alert alert-error">
        <div>Error message</div>
      </div>
      <div class="alert alert-success">
        <div>Success message</div>
      </div>
      """

      assert {:ok, :valid} = UIConsistencyValidator.validate_component(valid_alerts, "AlertTest")
    end
  end

  describe "responsive design validation" do
    test "validates mobile-first responsive patterns" do
      valid_responsive = """
      <div class="container mx-auto px-4 sm:px-6 lg:px-8">
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          <div class="card">Item 1</div>
          <div class="card">Item 2</div>
          <div class="card">Item 3</div>
        </div>
      </div>
      """

      assert {:ok, :valid} =
               UIConsistencyValidator.validate_component(valid_responsive, "ResponsiveTest")
    end

    test "detects non-mobile-first patterns" do
      invalid_responsive = """
      <div class="grid md:grid-cols-2 lg:grid-cols-3">
        <div>Content</div>
      </div>
      """

      assert {:error, violations} =
               UIConsistencyValidator.validate_component(invalid_responsive, "ResponsiveTest")

      assert Enum.any?(violations, &String.contains?(&1, "mobile-first"))
    end
  end

  describe "accessibility validation" do
    test "validates proper ARIA labels" do
      valid_accessibility = """
      <button aria-label="Close dialog">×</button>
      <img src="logo.png" alt="Company logo" />
      <label>
        <span class="label">Email</span>
        <input type="email" class="input" />
      </label>
      """

      assert {:ok, :valid} =
               UIConsistencyValidator.validate_component(valid_accessibility, "AccessibilityTest")
    end

    test "validates form accessibility" do
      valid_form = """
      <form>
        <label>
          <span class="label">Name</span>
          <input type="text" class="input" required />
        </label>
        <button type="submit" class="btn btn-primary">Submit</button>
      </form>
      """

      assert {:ok, :valid} = UIConsistencyValidator.validate_component(valid_form, "FormTest")
    end
  end

  describe "component reuse validation" do
    test "validates proper component reuse patterns" do
      valid_reuse = """
      <.messages
        messages={@messages}
        streaming={@streaming}
        stream_buffer={@stream_buffer}
        conversation_id={@conversation_id}
      />
      """

      assert {:ok, :valid} = UIConsistencyValidator.validate_component(valid_reuse, "ReuseTest")
    end

    test "validates error component reuse" do
      valid_error_reuse = """
      <.live_component
        module={AgentWebWeb.ErrorDisplayComponent}
        id="error-display"
        error={@error}
        error_type={@error_type}
        context={@context}
        recovery_actions={@recovery_actions}
      />
      """

      assert {:ok, :valid} =
               UIConsistencyValidator.validate_component(valid_error_reuse, "ErrorReuseTest")
    end
  end
end
