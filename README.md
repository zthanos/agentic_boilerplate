# Agentic Boilerplate (Elixir/Phoenix)

This repository is an **agentic application template** built on **Elixir Umbrella + Phoenix + SQLite**.
It is intended to be reused as a starter kit for experimenting with **agentic AI design patterns**
(e.g., Reflection, Planning) while keeping the **core logic in Elixir modules** and using the web layer
as a lightweight wrapper for setup, monitoring, and interactive testing.

## Goals

- Provide a reusable umbrella structure:
  - `agent_core`: pure domain/flow logic (no I/O)
  - `agent_runtime`: orchestration + ports (LLM client, storage, telemetry)
  - `agent_web`: Phoenix wrapper (Setup / Monitor / Chat)
- Enable quick experiments with patterns (Reflection first, Planning next)
- Provide **observability** for token usage and cost estimates
- Keep the implementation **simple** and avoid premature abstractions

## Project Structure

