defmodule AgentWebWeb.AdminAccessibility do
  @moduledoc """
  Accessibility utilities and helpers for the admin dashboard.

  Provides WCAG 2.1 compliant features including:
  - Keyboard navigation support
  - Screen reader compatibility
  - Focus management
  - ARIA labels and semantic HTML
  - High contrast and reduced motion support
  """

  @doc """
  Generates accessible navigation attributes for interactive elements.

  ## Examples

      <button {nav_attrs("main-menu", 1, 5)}>Menu Item 1</button>
  """
  def nav_attrs(group_name, position, total) do
    %{
      "aria-setsize" => total,
      "aria-posinset" => position,
      "role" => "menuitem",
      "data-nav-group" => group_name
    }
  end

  @doc """
  Generates ARIA attributes for form controls with validation states.

  ## Examples

      <input {form_control_attrs("email", @form[:email], required: true)} />
  """
  def form_control_attrs(field_name, field, opts \\ []) do
    required = Keyword.get(opts, :required, false)
    describedby = Keyword.get(opts, :describedby, [])

    base_attrs = %{
      "id" => "#{field_name}-input",
      "name" => field_name,
      "aria-label" => humanize_field_name(field_name)
    }

    attrs =
      if required do
        Map.put(base_attrs, "aria-required", "true")
      else
        base_attrs
      end

    attrs =
      if field && field.errors != [] do
        attrs
        |> Map.put("aria-invalid", "true")
        |> Map.put("aria-describedby", "#{field_name}-error " <> Enum.join(describedby, " "))
      else
        if describedby != [] do
          Map.put(attrs, "aria-describedby", Enum.join(describedby, " "))
        else
          attrs
        end
      end

    attrs
  end

  @doc """
  Generates accessible table attributes with sorting and filtering support.

  ## Examples

      <table {table_attrs("users-table", sortable: true, filterable: true)}>
  """
  def table_attrs(table_id, opts \\ []) do
    sortable = Keyword.get(opts, :sortable, false)
    filterable = Keyword.get(opts, :filterable, false)

    base_attrs = %{
      "id" => table_id,
      "role" => "table",
      "aria-label" => "Data table"
    }

    attrs =
      if sortable do
        Map.put(base_attrs, "aria-sort", "none")
      else
        base_attrs
      end

    if filterable do
      Map.put(attrs, "aria-describedby", "#{table_id}-filter-info")
    else
      attrs
    end
  end

  @doc """
  Generates accessible modal dialog attributes.

  ## Examples

      <div {modal_attrs("confirm-dialog", "Confirm Action")}>
  """
  def modal_attrs(modal_id, _title) do
    %{
      "id" => modal_id,
      "role" => "dialog",
      "aria-modal" => "true",
      "aria-labelledby" => "#{modal_id}-title",
      "aria-describedby" => "#{modal_id}-description",
      "tabindex" => "-1"
    }
  end

  @doc """
  Generates accessible button attributes with state information.

  ## Examples

      <button {button_attrs("toggle-sidebar", pressed: @sidebar_collapsed)}>
  """
  def button_attrs(button_id, opts \\ []) do
    pressed = Keyword.get(opts, :pressed, nil)
    expanded = Keyword.get(opts, :expanded, nil)
    controls = Keyword.get(opts, :controls, nil)
    disabled = Keyword.get(opts, :disabled, false)

    base_attrs = %{
      "id" => button_id,
      "type" => "button"
    }

    attrs =
      if pressed != nil do
        Map.put(base_attrs, "aria-pressed", to_string(pressed))
      else
        base_attrs
      end

    attrs =
      if expanded != nil do
        Map.put(attrs, "aria-expanded", to_string(expanded))
      else
        attrs
      end

    attrs =
      if controls do
        Map.put(attrs, "aria-controls", controls)
      else
        attrs
      end

    if disabled do
      Map.put(attrs, "aria-disabled", "true")
    else
      attrs
    end
  end

  @doc """
  Generates accessible status/alert attributes.

  ## Examples

      <div {status_attrs("system-status", :polite)}>System is healthy</div>
  """
  def status_attrs(status_id, live_type \\ :polite) do
    %{
      "id" => status_id,
      "role" => "status",
      "aria-live" => to_string(live_type),
      "aria-atomic" => "true"
    }
  end

  @doc """
  Generates accessible breadcrumb navigation attributes.

  ## Examples

      <nav {breadcrumb_attrs("main-breadcrumb")}>
  """
  def breadcrumb_attrs(nav_id) do
    %{
      "id" => nav_id,
      "role" => "navigation",
      "aria-label" => "Breadcrumb navigation"
    }
  end

  @doc """
  Generates accessible tab panel attributes.

  ## Examples

      <div {tab_panel_attrs("settings-general", "general-tab", selected: true)}>
  """
  def tab_panel_attrs(panel_id, tab_id, opts \\ []) do
    selected = Keyword.get(opts, :selected, false)

    %{
      "id" => panel_id,
      "role" => "tabpanel",
      "aria-labelledby" => tab_id,
      "tabindex" => if(selected, do: "0", else: "-1"),
      "hidden" => if(selected, do: nil, else: "")
    }
  end

  @doc """
  Generates accessible tab attributes.

  ## Examples

      <button {tab_attrs("general-tab", "settings-general", selected: true)}>
  """
  def tab_attrs(tab_id, panel_id, opts \\ []) do
    selected = Keyword.get(opts, :selected, false)

    %{
      "id" => tab_id,
      "role" => "tab",
      "aria-controls" => panel_id,
      "aria-selected" => to_string(selected),
      "tabindex" => if(selected, do: "0", else: "-1")
    }
  end

  @doc """
  Generates skip link attributes for keyboard navigation.

  ## Examples

      <a {skip_link_attrs("main-content")}>Skip to main content</a>
  """
  def skip_link_attrs(target_id) do
    %{
      "href" => "##{target_id}",
      "class" =>
        "skip-link sr-only focus:not-sr-only focus:absolute focus:top-4 focus:left-4 focus:z-50 focus:px-4 focus:py-2 focus:bg-primary focus:text-primary-content focus:rounded",
      "aria-label" => "Skip to main content"
    }
  end

  @doc """
  Generates accessible loading state attributes.

  ## Examples

      <div {loading_attrs("data-loading")}>Loading...</div>
  """
  def loading_attrs(loading_id) do
    %{
      "id" => loading_id,
      "role" => "status",
      "aria-live" => "polite",
      "aria-label" => "Loading content"
    }
  end

  @doc """
  Generates accessible error message attributes.

  ## Examples

      <div {error_attrs("form-error")}>Invalid input</div>
  """
  def error_attrs(error_id) do
    %{
      "id" => error_id,
      "role" => "alert",
      "aria-live" => "assertive",
      "aria-atomic" => "true"
    }
  end

  @doc """
  Generates accessible search/filter attributes.

  ## Examples

      <input {search_attrs("table-search", "users-table")}>
  """
  def search_attrs(search_id, target_id) do
    %{
      "id" => search_id,
      "type" => "search",
      "role" => "searchbox",
      "aria-label" => "Search and filter results",
      "aria-controls" => target_id,
      "aria-describedby" => "#{search_id}-help"
    }
  end

  @doc """
  Generates accessible menu attributes.

  ## Examples

      <ul {menu_attrs("user-menu", "user-menu-button")}>
  """
  def menu_attrs(menu_id, button_id) do
    %{
      "id" => menu_id,
      "role" => "menu",
      "aria-labelledby" => button_id,
      "tabindex" => "-1"
    }
  end

  @doc """
  Generates accessible progress bar attributes.

  ## Examples

      <div {progress_attrs("upload-progress", 75, 100)}>
  """
  def progress_attrs(progress_id, value, max) do
    %{
      "id" => progress_id,
      "role" => "progressbar",
      "aria-valuenow" => to_string(value),
      "aria-valuemin" => "0",
      "aria-valuemax" => to_string(max),
      "aria-label" => "Progress: #{value} of #{max}"
    }
  end

  @doc """
  Humanizes field names for accessibility labels.

  ## Examples

      iex> humanize_field_name("first_name")
      "First name"

      iex> humanize_field_name("email_address")
      "Email address"
  """
  def humanize_field_name(field_name) when is_atom(field_name) do
    humanize_field_name(Atom.to_string(field_name))
  end

  def humanize_field_name(field_name) when is_binary(field_name) do
    field_name
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  @doc """
  Generates keyboard navigation event handlers.

  ## Examples

      <div {keyboard_nav_handlers("menu")}>
  """
  def keyboard_nav_handlers(nav_type) do
    case nav_type do
      "menu" ->
        %{
          "phx-keydown" => "handle_menu_keydown",
          "phx-key" => "ArrowDown,ArrowUp,Enter,Escape,Home,End"
        }

      "tabs" ->
        %{
          "phx-keydown" => "handle_tab_keydown",
          "phx-key" => "ArrowLeft,ArrowRight,Home,End"
        }

      "table" ->
        %{
          "phx-keydown" => "handle_table_keydown",
          "phx-key" => "ArrowDown,ArrowUp,ArrowLeft,ArrowRight,Enter,Space"
        }

      _other ->
        %{}
    end
  end

  @doc """
  Generates focus trap attributes for modal dialogs.

  ## Examples

      <div {focus_trap_attrs("modal-content")}>
  """
  def focus_trap_attrs(container_id) do
    %{
      "phx-hook" => "FocusTrap",
      "data-focus-trap-container" => container_id
    }
  end

  @doc """
  Generates reduced motion safe animation classes.

  ## Examples

      <div class={motion_safe_classes(["animate-spin", "transition-all"])}>
  """
  def motion_safe_classes(animation_classes) when is_list(animation_classes) do
    Enum.map(animation_classes, fn class ->
      if String.contains?(class, "animate-") or String.contains?(class, "transition") do
        "motion-safe:#{class}"
      else
        class
      end
    end)
  end

  def motion_safe_classes(animation_class) when is_binary(animation_class) do
    motion_safe_classes([animation_class]) |> List.first()
  end

  @doc """
  Generates high contrast compatible color classes.

  ## Examples

      <div class={high_contrast_classes("text-gray-500")}>
  """
  def high_contrast_classes(color_class) do
    # Map low contrast colors to high contrast alternatives
    contrast_map = %{
      "text-gray-400" => "contrast-more:text-gray-900",
      "text-gray-500" => "contrast-more:text-gray-900",
      "text-gray-600" => "contrast-more:text-gray-900",
      "bg-gray-100" => "contrast-more:bg-white contrast-more:border",
      "bg-gray-200" => "contrast-more:bg-white contrast-more:border-2",
      "border-gray-200" => "contrast-more:border-gray-900",
      "border-gray-300" => "contrast-more:border-gray-900"
    }

    high_contrast = Map.get(contrast_map, color_class, "")

    if high_contrast != "" do
      "#{color_class} #{high_contrast}"
    else
      color_class
    end
  end

  @doc """
  Validates accessibility compliance for component attributes.

  ## Examples

      iex> validate_accessibility(%{"role" => "button"}, [:role])
      :ok

      iex> validate_accessibility(%{}, [:aria_label])
      {:error, "Missing required accessibility attribute: aria-label"}
  """
  def validate_accessibility(attrs, required_attrs) do
    missing_attrs =
      required_attrs
      |> Enum.map(&normalize_attr_name/1)
      |> Enum.reject(fn attr -> Map.has_key?(attrs, attr) end)

    case missing_attrs do
      [] -> :ok
      [attr | _] -> {:error, "Missing required accessibility attribute: #{attr}"}
    end
  end

  # Helper function to normalize attribute names
  defp normalize_attr_name(attr) when is_atom(attr) do
    attr |> Atom.to_string() |> String.replace("_", "-")
  end

  defp normalize_attr_name(attr) when is_binary(attr) do
    String.replace(attr, "_", "-")
  end
end
