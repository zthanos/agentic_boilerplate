defmodule AgentCore.Stores.LLMProfileStore do
  @moduledoc """
  Behavior for LLM profile storage operations.

  This behavior defines the contract for storing and retrieving LLM profiles
  in the agent system. Implementations should handle persistence and provide
  domain-level operations for LLM profile management.
  """

  alias AgentCore.Llm.LLMProfile

  @type profile_id :: String.t()
  @type profile_name :: String.t()

  @doc """
  Store an LLM profile.
  Returns {:ok, profile_id} on success, {:error, reason} on failure.
  """
  @callback put(LLMProfile.t()) :: {:ok, profile_id()} | {:error, term()}

  @doc """
  Retrieve an LLM profile by ID.
  Returns {:ok, profile} on success, :error if not found.
  """
  @callback get(profile_id()) :: {:ok, LLMProfile.t()} | :error

  @doc """
  List all LLM profiles with optional filtering.
  """
  @callback list(keyword()) :: [LLMProfile.t()]

  @doc """
  Delete an LLM profile by ID.
  Returns :ok on success, {:error, reason} on failure.
  """
  @callback delete(profile_id()) :: :ok | {:error, term()}

  @doc """
  Check if a profile name is available.
  """
  @callback name_available?(profile_name()) :: boolean()
end
