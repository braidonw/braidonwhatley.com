defmodule AppWeb.UI do
  @moduledoc """
  The core UI component set for the Braidon Whatley design system.

  Each component is a thin Phoenix function wrapper over a CUBE CSS *block*
  (`assets/css/styles/blocks/c-*.css`) that consumes the design-system tokens
  (`assets/css/styles/global/tokens/*.css`). The block owns the look; the
  component owns the markup contract.

  Components, by block:

    * `bw_btn`      → `c-btn`      — neutral / accent / ghost, sizes sm·lg
    * `bw_badge`    → `c-badge`    — ink / accent / outline / dot status chips
    * `bw_tag`      → `c-tag`      — the mono overline used as print furniture
    * `bw_card`     → `c-card`     — heavy-bordered, optionally hard-shadowed
    * `bw_callout`  → `c-callout`  — sunken newsprint aside with an accent eyebrow
    * `bw_field`    → `c-field`    — label + control + hint/error wrapper
    * `bw_input` / `bw_textarea` → `c-input` — hard-focus text controls
  """
  use Phoenix.Component

  # ─── Button ───────────────────────────────────────────────────────

  @doc """
  Button with three variants × three sizes.

  Renders a `<button>` by default; pass `href` to render an `<a>` instead.
  `kbd` appends a dimmed keyboard hint.
  """
  attr :variant, :string, default: "neutral", values: ~w(neutral accent ghost)
  attr :size, :string, default: nil, values: [nil, "sm", "lg"]
  attr :type, :string, default: "button"
  attr :kbd, :string, default: nil
  attr :href, :string, default: nil
  attr :class, :string, default: nil

  attr :rest, :global,
    include: ~w(disabled target rel name value form phx-click phx-value-tag phx-disable-with)

  slot :inner_block, required: true

  def bw_btn(assigns) do
    assigns =
      assign(assigns, :classes, [
        "c-btn",
        assigns.variant != "neutral" && "c-btn--#{assigns.variant}",
        assigns.size && "c-btn--#{assigns.size}",
        assigns[:class]
      ])

    ~H"""
    <a :if={@href} class={@classes} href={@href} {@rest}>
      {render_slot(@inner_block)}<span :if={@kbd} class="c-btn__kbd">{@kbd}</span>
    </a>
    <button :if={!@href} class={@classes} type={@type} {@rest}>
      {render_slot(@inner_block)}<span :if={@kbd} class="c-btn__kbd">{@kbd}</span>
    </button>
    """
  end

  # ─── Badge ────────────────────────────────────────────────────────

  @doc "Small mono status chip. Variants: ink (default) · accent · outline · dot."
  attr :variant, :string, default: "ink", values: ~w(ink accent outline dot)
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def bw_badge(assigns) do
    ~H"""
    <span
      class={["c-badge", @variant != "ink" && "c-badge--#{@variant}", @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  # ─── Tag (overline) ───────────────────────────────────────────────

  @doc "Mono overline / kicker — print furniture. Variants: muted (default) · strong · accent."
  attr :variant, :string, default: "muted", values: ~w(muted strong accent)
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def bw_tag(assigns) do
    ~H"""
    <span
      class={["c-tag", @variant != "muted" && "c-tag--#{@variant}", @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  # ─── Card ─────────────────────────────────────────────────────────

  @doc """
  Heavy-bordered container. Optional `shadow` (`hard` | `accent`) and a
  `head`/`foot` slot for the mono eyebrow and flush footer rule.
  """
  attr :shadow, :string, default: nil, values: [nil, "hard", "accent"]
  attr :sunken, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global

  slot :head do
    attr :ink, :boolean
  end

  slot :foot
  slot :inner_block, required: true

  def bw_card(assigns) do
    ~H"""
    <div
      class={[
        "c-card",
        @shadow == "hard" && "c-card--shadow",
        @shadow == "accent" && "c-card--accent-shadow",
        @sunken && "c-card--sunken",
        @class
      ]}
      {@rest}
    >
      <div :for={head <- @head} class={["c-card__head", head[:ink] && "c-card__head--ink"]}>
        {render_slot(head)}
      </div>
      <div class="c-card__body">{render_slot(@inner_block)}</div>
      <div :for={foot <- @foot} class="c-card__foot">{render_slot(foot)}</div>
    </div>
    """
  end

  # ─── Callout ──────────────────────────────────────────────────────

  @doc "Sunken newsprint aside with an accent mono eyebrow. Used for hints and notes."
  attr :eyebrow, :string, default: nil
  attr :flush, :boolean, default: false, doc: "drop the box border, keep only a top rule"
  attr :accent, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def bw_callout(assigns) do
    ~H"""
    <div
      class={[
        "c-callout",
        @flush && "c-callout--flush",
        @accent && "c-callout--accent",
        @class
      ]}
      {@rest}
    >
      <div :if={@eyebrow} class="c-callout__eyebrow">{@eyebrow}</div>
      <div class="c-callout__body">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  # ─── Forms ────────────────────────────────────────────────────────

  @doc "Field wrapper — label, control, hint, error. Use with `bw_input`/`bw_textarea`."
  attr :label, :string, required: true
  attr :for, :string, default: nil
  attr :required, :boolean, default: false
  attr :hint, :string, default: nil
  attr :error, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def bw_field(assigns) do
    ~H"""
    <div class={["c-field", @class]}>
      <label class="c-field__label" for={@for} data-required={@required && ""}>
        {@label}
      </label>
      {render_slot(@inner_block)}
      <div :if={@hint && !@error} class="c-field__hint">{@hint}</div>
      <div :if={@error} class="c-field__error">{@error}</div>
    </div>
    """
  end

  @doc "Single-line text input. Pass `prefix` for `@`/`$`/`/` style affixes."
  attr :type, :string, default: "text"
  attr :name, :string, default: nil
  attr :id, :string, default: nil
  attr :value, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :prefix, :string, default: nil
  attr :invalid, :boolean, default: false
  attr :field, Phoenix.HTML.FormField, default: nil

  attr :rest, :global,
    include:
      ~w(autocomplete autofocus disabled minlength maxlength pattern readonly required inputmode)

  def bw_input(assigns) do
    assigns = field_to_attrs(assigns)

    ~H"""
    <div :if={@prefix} class="c-input-group">
      <span class="c-input-group__prefix">{@prefix}</span>
      <input
        class="c-input"
        type={@type}
        name={@name}
        id={@id}
        value={@value}
        placeholder={@placeholder}
        aria-invalid={@invalid && "true"}
        {@rest}
      />
    </div>
    <input
      :if={!@prefix}
      class="c-input"
      type={@type}
      name={@name}
      id={@id}
      value={@value}
      placeholder={@placeholder}
      aria-invalid={@invalid && "true"}
      {@rest}
    />
    """
  end

  @doc "Multi-line text input."
  attr :name, :string, default: nil
  attr :id, :string, default: nil
  attr :value, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :rows, :integer, default: 4
  attr :invalid, :boolean, default: false
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :rest, :global, include: ~w(autocomplete disabled maxlength minlength readonly required)

  def bw_textarea(assigns) do
    assigns = field_to_attrs(assigns)

    ~H"""
    <textarea
      class="c-textarea"
      name={@name}
      id={@id}
      placeholder={@placeholder}
      rows={@rows}
      aria-invalid={@invalid && "true"}
      {@rest}
    >{@value}</textarea>
    """
  end

  # ─── helpers ──────────────────────────────────────────────────────

  defp field_to_attrs(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:id, fn -> field.id end)
    |> assign_new(:value, fn -> field.value end)
    |> assign(:invalid, field.errors != [])
  end

  defp field_to_attrs(assigns), do: assigns
end
