# UI Consistency Validation Guide

This guide explains how to use the UI consistency validation system for the agent testing interface.

## Overview

The UI consistency validation system ensures that all components in the agent testing interface follow the established design system patterns, including:

- **DaisyUI + Tailwind CSS** design system compliance
- **Responsive design** patterns with mobile-first approach
- **Color consistency** using semantic color classes
- **Component reuse** and styling consistency
- **Accessibility standards** compliance

## Quick Start

### Run Quick Check

```bash
mix ui_consistency --quick
```

This provides a fast overview of which components have issues.

### Run Full Analysis

```bash
mix ui_consistency
```

This runs a comprehensive check with detailed violation reports.

### Check Specific Component

```bash
mix ui_consistency --component apps/agent_web/lib/agent_web_web/live/agent_testing_live.ex
```

### Generate Report

```bash
mix ui_consistency --report
```

This generates a detailed markdown report saved to `ui_consistency_report.md`.

### Get Recommendations

```bash
mix ui_consistency --recommendations
```

This shows detailed recommendations for fixing UI consistency issues.

## Design System Standards

### DaisyUI Component Usage

✅ **Correct Usage:**
```html
<div class="card bg-base-200 shadow-xl">
  <div class="card-body">
    <button class="btn btn-primary">Action</button>
    <div class="alert alert-info">Message</div>
  </div>
</div>
```

❌ **Avoid:**
```html
<div style="background: #f0f0f0; padding: 20px;">
  <button style="background: blue; color: white;">Action</button>
</div>
```

### Semantic Color Classes

✅ **Use Semantic Colors:**
- `primary`, `secondary`, `accent` for branding
- `info`, `success`, `warning`, `error` for status
- `base-100`, `base-200`, `base-300` for backgrounds
- `base-content` for text

❌ **Avoid Raw Colors:**
- `bg-red-500`, `text-blue-600`, `border-green-400`

### Responsive Design Patterns

✅ **Mobile-First Approach:**
```html
<div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 px-4 sm:px-6 lg:px-8">
  <div class="card">Content</div>
</div>
```

❌ **Desktop-First (Avoid):**
```html
<div class="grid grid-cols-3 md:grid-cols-2 sm:grid-cols-1">
  <div>Content</div>
</div>
```

### Component Reuse

✅ **Reuse Existing Components:**
```elixir
<.messages
  messages={@messages}
  streaming={@streaming}
  stream_buffer={@stream_buffer}
  conversation_id={@conversation_id}
/>

<.live_component
  module={AgentWebWeb.ErrorDisplayComponent}
  id="error-display"
  error={@error}
  error_type={@error_type}
/>
```

### Accessibility Standards

✅ **Proper Accessibility:**
```html
<!-- Buttons with meaningful text -->
<button class="btn btn-primary">Save Changes</button>

<!-- Buttons with icons need aria-label -->
<button class="btn btn-ghost" aria-label="Close dialog">×</button>

<!-- Form inputs with labels -->
<label>
  <span class="label">Email Address</span>
  <input type="email" class="input input-bordered" />
</label>

<!-- Images with alt text -->
<img src="logo.png" alt="Company Logo" />
```

## Common Violations and Fixes

### 1. Inline Styles

**Issue:** Using `style` attributes instead of Tailwind classes

**Fix:** Replace inline styles with Tailwind utility classes
```html
<!-- Before -->
<div style="width: 50%; margin: 10px;">

<!-- After -->
<div class="w-1/2 m-2.5">
```

### 2. Non-Responsive Padding

**Issue:** Using fixed padding without responsive breakpoints

**Fix:** Use responsive padding patterns
```html
<!-- Before -->
<div class="px-4">

<!-- After -->
<div class="px-4 sm:px-6 lg:px-8">
```

### 3. Missing Form Labels

**Issue:** Form inputs without proper labeling

**Fix:** Wrap inputs in labels or add aria-label
```html
<!-- Before -->
<input type="text" placeholder="Enter name" />

<!-- After -->
<label>
  <span class="label">Name</span>
  <input type="text" class="input input-bordered" />
</label>
```

### 4. Raw Color Usage

**Issue:** Using specific color values instead of semantic classes

**Fix:** Use semantic color classes
```html
<!-- Before -->
<div class="bg-red-500 text-white">

<!-- After -->
<div class="bg-error text-error-content">
```

## Integration with Development Workflow

### Pre-commit Hook

Add UI consistency check to your pre-commit workflow:

```bash
# In your pre-commit script
mix ui_consistency --quick
if [ $? -ne 0 ]; then
  echo "UI consistency issues found. Run 'mix ui_consistency' for details."
  exit 1
fi
```

### CI/CD Integration

Add to your CI pipeline:

```yaml
- name: Check UI Consistency
  run: mix ui_consistency --quick
```

### IDE Integration

You can run checks on individual files during development:

```bash
mix ui_consistency --component path/to/your/component.ex
```

## Validation Rules

### Design System Compliance
- ✅ DaisyUI component classes (card, btn, alert, etc.)
- ✅ Consistent Tailwind spacing (p-2 to p-6, m-2 to m-6)
- ❌ Inline styles
- ❌ Raw color classes (bg-red-*, text-blue-*, etc.)

### Responsive Design
- ✅ Mobile-first breakpoints (sm:, md:, lg:)
- ✅ Responsive grid patterns
- ✅ Responsive spacing
- ❌ Desktop-first approach

### Color Consistency
- ✅ Semantic colors for alerts (alert-error, alert-info)
- ✅ Semantic colors for buttons (btn-primary, btn-secondary)
- ✅ Base colors for backgrounds (base-100, base-200)
- ❌ Raw Tailwind colors

### Component Reuse
- ✅ Using MessagesComponent for message display
- ✅ Using ErrorDisplayComponent for errors
- ✅ Using CoreComponents for forms
- ❌ Duplicating existing component functionality

### Accessibility
- ✅ ARIA labels on interactive elements
- ✅ Proper form labeling
- ✅ Alt text on images
- ✅ Proper heading hierarchy (h1 → h2 → h3)
- ❌ Unlabeled interactive elements
- ❌ Missing alt text
- ❌ Improper heading structure

## Customizing Validation Rules

You can extend the validation system by modifying `AgentWeb.UIConsistencyValidator`:

```elixir
# Add custom validation rules
defp check_custom_patterns(violations, content, component_name) do
  # Your custom validation logic here
  violations
end
```

## Troubleshooting

### Common Issues

1. **False Positives**: If the validator flags valid code, check if the pattern matching is too strict
2. **Missing Violations**: If issues aren't caught, the regex patterns may need adjustment
3. **Performance**: For large codebases, consider running checks only on changed files

### Getting Help

- Run `mix ui_consistency --help` for usage information
- Check the validation rules in `AgentWeb.UIConsistencyValidator`
- Review the test cases in `AgentWeb.UIConsistencyValidatorTest`

## Best Practices

1. **Run checks frequently** during development
2. **Fix violations incrementally** rather than all at once
3. **Use semantic classes** consistently across components
4. **Follow mobile-first** responsive design patterns
5. **Reuse existing components** whenever possible
6. **Maintain accessibility** standards from the start

## Example Workflow

1. **Develop component** using established patterns
2. **Run quick check**: `mix ui_consistency --quick`
3. **Fix any violations** found
4. **Run full check**: `mix ui_consistency`
5. **Commit changes** once all checks pass

This ensures consistent, accessible, and maintainable UI code across the entire agent testing interface.