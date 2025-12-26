defmodule AgentCore.RunStore.SerializationTest do
  use ExUnit.Case, async: true

  alias AgentCore.RunStore.Serialization

  test "deep_stringify_keys/1 converts atom keys recursively" do
    input = %{
      :a => 1,
      "b" => %{:c => 2, :d => [%{:e => 3}, %{:f => 4}]},
      :g => [:x, %{:h => 1}]
    }

    out = Serialization.deep_stringify_keys(input)

    assert out["a"] == 1
    assert out["b"]["c"] == 2
    assert out["b"]["d"] |> Enum.at(0) |> Map.get("e") == 3
    assert out["g"] == [:x, %{"h" => 1}]
  end

  test "deep_sort/1 sorts map keys and scalar lists" do
    input = %{"b" => 1, "a" => 2, "c" => ["z", "a", "m"]}
    out = Serialization.deep_sort(input)

    assert Map.keys(out) == ["a", "b", "c"]
    assert out["c"] == ["a", "m", "z"]
  end
end
