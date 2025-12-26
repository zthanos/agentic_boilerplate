defmodule AgentCore.Llm.Tools.RegistryTest do
  use ExUnit.Case, async: true

  alias AgentCore.Llm.Tools.Registry
  alias AgentCore.Llm.Tools.ToolSpec

  test "normalize_tools: nil -> []" do
    assert {:ok, []} = Registry.normalize_tools(nil)
  end

  test "normalize_tools: :__clear__ -> []" do
    assert {:ok, []} = Registry.normalize_tools(:__clear__)
  end

  test "normalize_tools: atoms/strings resolve aliases and sort by id" do
    input = [:calc, "web", "files.read"]

    assert {:ok, specs} = Registry.normalize_tools(input)
    assert Enum.map(specs, & &1.id) == ["files.read", "math.eval", "web.search"]
  end

  test "normalize_tools: :__clear__ inside list keeps suffix after last clear" do
    input = ["web.search", :__clear__, "files", "calc"]

    assert {:ok, specs} = Registry.normalize_tools(input)
    assert Enum.map(specs, & &1.id) == ["files.read", "math.eval"]
  end

  test "normalize_tools: multiple :__clear__ keeps only after last one" do
    input = ["web.search", :__clear__, "files.read", :__clear__, "calc"]

    assert {:ok, specs} = Registry.normalize_tools(input)
    assert Enum.map(specs, & &1.id) == ["math.eval"]
  end

  test "normalize_tools: dedup keeps first occurrence then ordering applies" do
    input = ["web", "web.search", "web_search", "files", "files.read"]

    assert {:ok, specs} = Registry.normalize_tools(input)
    assert Enum.map(specs, & &1.id) == ["files.read", "web.search"]
  end

  test "normalize_tools: rejects unknown tool by default" do
    assert {:error, {:unknown_tool, "unknown.tool"}} =
             Registry.normalize_tools(["unknown.tool"])
  end

  test "normalize_tools: allow_unknown? true permits unknown ids (still canonicalized/ordered)" do
    assert {:ok, specs} =
             Registry.normalize_tools(["unknown.tool", "web"], allow_unknown?: true)

    assert Enum.map(specs, & &1.id) == ["unknown.tool", "web.search"]
  end

  test "normalize_tools: allowed list restricts tools (strict by default)" do
    assert {:error, {:tool_not_allowed, "files.read"}} =
             Registry.normalize_tools(["files.read"], allowed: ["web.search"])

    assert {:ok, specs} = Registry.normalize_tools(["web"], allowed: ["web.search"])
    assert Enum.map(specs, & &1.id) == ["web.search"]
  end

  test "normalize_tools: accepts ToolSpec and map inputs" do
    input = [
      ToolSpec.new("calculator"),
      %{"id" => "files"},
      %{id: "web_search", name: "WS"}
    ]

    assert {:ok, specs} = Registry.normalize_tools(input)
    assert Enum.map(specs, & &1.id) == ["files.read", "math.eval", "web.search"]
  end

  test "normalize_tools: stable ordering option keeps insertion order after dedup" do
    input = ["web", "files", "calc"]

    assert {:ok, specs} = Registry.normalize_tools(input, ordering: :stable)
    assert Enum.map(specs, & &1.id) == ["web.search", "files.read", "math.eval"]
  end
end
