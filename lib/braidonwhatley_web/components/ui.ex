defmodule AppWeb.UI do
  @moduledoc """
  Engineering-notebook UI components — function components that wrap the
  CUBE blocks defined in `assets/css/styles/blocks/*.css`.

  Naming follows the kitchen-sink reference: each `c-*` block has a
  matching `bw_*` Phoenix component, plus a small set of layout
  primitives (`bw_stack`, `bw_cluster`, `bw_sidebar`, `bw_grid`,
  `bw_page`) that wrap the `l-*` compositions.
  """
  use Phoenix.Component

  # ─── Compositions ─────────────────────────────────────────────────

  @doc "Outer page container — the `l-page` wrapper."
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def bw_page(assigns) do
    ~H"""
    <div class={["l-page", @class]} {@rest}>{render_slot(@inner_block)}</div>
    """
  end

  @doc "Vertical stack with consistent gap. Override via `space=\"s-2|s-3|s-5|s-6\"`."
  attr :space, :string, default: nil, values: [nil, "s-2", "s-3", "s-5", "s-6"]
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def bw_stack(assigns) do
    ~H"""
    <div class={["l-stack", @class]} data-space={@space} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc "Horizontal wrapping cluster — tag rows, button groups, breadcrumbs."
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def bw_cluster(assigns) do
    ~H"""
    <div class={["l-cluster", @class]} {@rest}>{render_slot(@inner_block)}</div>
    """
  end

  @doc "Sidebar layout — main content + skinny 220px rail."
  slot :main, required: true
  slot :rail, required: true
  attr :class, :string, default: nil

  def bw_sidebar(assigns) do
    ~H"""
    <div class={["l-sidebar", @class]}>
      <div>{render_slot(@main)}</div>
      <div>{render_slot(@rail)}</div>
    </div>
    """
  end

  @doc "Equal-column grid. Currently only 3-column; collapses to one column under 720px."
  attr :cols, :integer, default: 3, values: [3]
  attr :class, :string, default: nil
  slot :col, required: true

  def bw_grid(assigns) do
    ~H"""
    <div class={["l-grid-#{@cols}", @class]}>
      <div :for={col <- @col}>{render_slot(col)}</div>
    </div>
    """
  end

  # ─── Chrome ───────────────────────────────────────────────────────

  @doc "Top-of-page header. Brand on the left, nav on the right."
  attr :active, :atom, default: nil
  attr :brand, :string, default: "braidon whatley"
  attr :class, :string, default: nil

  slot :item, required: true do
    attr :id, :atom, required: true
    attr :href, :string, required: true
  end

  def bw_header(assigns) do
    ~H"""
    <header class={["c-header", @class]}>
      <div class="c-header__brand">
        <a href="/">{@brand}<span class="u-blink"></span></a>
      </div>
      <nav class="c-header__nav">
        <a
          :for={item <- @item}
          href={item.href}
          aria-current={if item.id == @active, do: "page"}
        >{render_slot(item)}</a>
      </nav>
    </header>
    """
  end

  @doc "Extended top bar with a tagline and a stacked nav row."
  attr :active, :atom, default: nil
  attr :brand, :string, default: "braidon whatley"
  attr :tagline, :string, default: nil
  attr :class, :string, default: nil

  slot :item, required: true do
    attr :id, :atom, required: true
    attr :href, :string, required: true
  end

  def bw_site_head(assigns) do
    ~H"""
    <header class={["c-site-head", @class]}>
      <div class="c-site-head__top">
        <div class="c-site-head__brand">
          <a href="/">{@brand}<span class="u-blink"></span></a>
        </div>
        <div :if={@tagline} class="c-site-head__tagline">{@tagline}</div>
      </div>
      <nav class="c-site-head__nav">
        <a
          :for={item <- @item}
          href={item.href}
          aria-current={if item.id == @active, do: "page"}
        >{render_slot(item)}</a>
      </nav>
    </header>
    """
  end

  @doc "Slash-separated breadcrumb. Last item is plain text via the `here` slot."
  slot :step do
    attr :href, :string, required: true
  end

  slot :here, required: true

  def bw_crumb(assigns) do
    ~H"""
    <nav class="c-crumb">
      <span :for={step <- @step}>
        <a href={step.href}>{render_slot(step)}</a>
        <span class="c-crumb__sep">/</span>
      </span>
      <span class="c-crumb__here">{render_slot(@here)}</span>
    </nav>
    """
  end

  @doc "Page header — serif h1 + dim lede. Used on writing/projects/tools."
  attr :title, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block

  def bw_page_head(assigns) do
    ~H"""
    <div class={["c-page-head", @class]}>
      <h1 class="c-page-head__title">{@title}</h1>
      <p :if={@inner_block != []} class="c-page-head__lede">
        {render_slot(@inner_block)}
      </p>
    </div>
    """
  end

  @doc "Larger sibling of `bw_page_head`. Optional kicker, lede, and actions row."
  attr :kicker, :string, default: nil
  attr :class, :string, default: nil

  slot :title, required: true
  slot :lede
  slot :actions

  def bw_hero(assigns) do
    ~H"""
    <section class={["c-hero", @class]}>
      <div :if={@kicker} class="c-hero__kicker">{@kicker}</div>
      <h1 class="c-hero__title">{render_slot(@title)}</h1>
      <p :if={@lede != []} class="c-hero__lede">{render_slot(@lede)}</p>
      <div :if={@actions != []} class="c-hero__actions">{render_slot(@actions)}</div>
    </section>
    """
  end

  @doc "Site footer — contact line, page number, optional local clock."
  attr :page, :integer, default: 1
  attr :clock, :string, default: nil
  attr :contact, :string, default: "hello@braidonwhatley.com · @bw on most things"

  def bw_footer(assigns) do
    ~H"""
    <footer class="c-footer">
      <span>↳ {@contact}</span>
      <span>
        notebook iv · pp. {String.pad_leading(Integer.to_string(@page), 3, "0")}<%= if @clock do %> · {@clock}<% end %>
      </span>
    </footer>
    """
  end

  # ─── Blocks ───────────────────────────────────────────────────────

  @doc """
  Three button variants × three sizes. Optional `kbd` for keyboard hints.

  Renders a `<button>` by default; pass `href` to render an `<a>` instead.
  """
  attr :variant, :string, default: "neutral", values: ~w(neutral accent ghost)
  attr :size, :string, default: nil, values: [nil, "sm", "lg"]
  attr :type, :string, default: "button"
  attr :kbd, :string, default: nil
  attr :href, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled phx-click phx-value-tag form name value)

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

  @doc "Numbered eyebrow heading with a trailing dotted rule."
  attr :num, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def bw_section_h(assigns) do
    ~H"""
    <div class={["c-section-h", @class]}>
      <span :if={@num} class="c-section-h__num">§{@num}</span>
      <h2 class="c-section-h__t">{render_slot(@inner_block)}</h2>
      <span class="c-section-h__line"></span>
    </div>
    """
  end

  @doc "Vertical list of links — used three times on the home page."
  attr :class, :string, default: nil

  slot :row, required: true do
    attr :href, :string, required: true
    attr :meta, :string
  end

  def bw_linklist(assigns) do
    ~H"""
    <ul class={["c-linklist", @class]}>
      <li :for={row <- @row} class="c-linklist__item">
        <a href={row.href}>{render_slot(row)}</a>
        <span :if={row[:meta]} class="c-linklist__meta">{row.meta}</span>
      </li>
    </ul>
    """
  end

  @doc """
  Single row in the writing index. Date / title+blurb / words+tag.

  `words` accepts an integer or a pre-formatted string ("1,840").
  """
  attr :date, :string, required: true
  attr :title, :string, required: true
  attr :blurb, :string, default: nil
  attr :words, :any, default: nil
  attr :tag, :string, default: nil
  attr :href, :string, required: true

  def bw_post_row(assigns) do
    ~H"""
    <a href={@href} class="c-post-row" style="text-decoration: none; color: inherit; border: 0;">
      <span class="c-post-row__date">{@date}</span>
      <div>
        <div class="c-post-row__title">{@title}</div>
        <div :if={@blurb} class="c-post-row__blurb">{@blurb}</div>
      </div>
      <span class="c-post-row__rt">
        <span :if={@words}>{@words} w</span>
        <br :if={@words && @tag} />
        <span :if={@tag} class="u-accent">#{@tag}</span>
      </span>
    </a>
    """
  end

  @doc "Single row in the projects index. Name+status / tagline / stack / metric."
  attr :name, :string, required: true
  attr :status, :atom, default: :live, values: ~w(live wip archived)a
  attr :status_label, :string, default: nil
  attr :tagline, :string, default: nil
  attr :stack, :string, default: nil
  attr :metric, :string, default: nil
  attr :href, :string, required: true

  def bw_project_row(assigns) do
    assigns =
      assign_new(assigns, :status_label, fn ->
        case assigns.status do
          :live -> "live"
          :wip -> "wip"
          :archived -> "archived"
        end
      end)

    ~H"""
    <a href={@href} class="c-project-row" style="text-decoration: none; color: inherit; border: 0;">
      <div>
        <div class="c-project-row__name">{@name}</div>
        <div class="c-project-row__status">
          <.bw_status_dot status={@status} />{@status_label}
        </div>
      </div>
      <div :if={@tagline} class="c-project-row__tagline">{@tagline}</div>
      <div :if={@stack} class="u-meta" style="text-align: right;">{@stack}</div>
      <div :if={@metric} class="u-meta" style="text-align: right;">{@metric}</div>
    </a>
    """
  end

  @doc "Coloured 8px dot for project status."
  attr :status, :atom, required: true, values: ~w(live wip archived)a

  def bw_status_dot(assigns) do
    ~H"""
    <span class="c-status-dot" data-status={@status}></span>
    """
  end

  @doc "Pill button for filters and segmented choices. `pressed` is the source of truth."
  attr :pressed, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(phx-click phx-value-tag disabled type)
  slot :inner_block, required: true

  def bw_pill(assigns) do
    ~H"""
    <button
      type="button"
      class={["c-pill", @class]}
      aria-pressed={to_string(@pressed)}
      {@rest}
    >{render_slot(@inner_block)}</button>
    """
  end

  @doc "\"NOW\" strip — what I'm doing right now, dashed border."
  attr :label, :string, default: "NOW"
  slot :inner_block, required: true
  slot :more

  def bw_now_strip(assigns) do
    ~H"""
    <div class="c-now-strip">
      <span class="c-now-strip__lbl">{@label}</span>
      <span class="c-now-strip__body">{render_slot(@inner_block)}</span>
      <span :if={@more != []} class="u-meta">{render_slot(@more)}</span>
    </div>
    """
  end

  @doc "Key/value fact rows — about-page side rail."
  attr :class, :string, default: nil

  slot :row, required: true do
    attr :k, :string, required: true
  end

  def bw_facts(assigns) do
    ~H"""
    <div class={["l-stack", @class]} style="border-top: 1px solid var(--c-ink-3); border-bottom: 1px solid var(--c-ink-3); padding: 12px 0;">
      <div :for={row <- @row} class="c-fact-row">
        <span class="c-fact-row__k">{row.k}</span>
        <span>{render_slot(row)}</span>
      </div>
    </div>
    """
  end

  @doc "Italic serif pull-quote with an accent bar on the left."
  slot :inner_block, required: true

  def bw_pullquote(assigns) do
    ~H"""
    <blockquote class="c-pullquote">{render_slot(@inner_block)}</blockquote>
    """
  end

  @doc "Inline interactive counter — pairs with a LiveView phx-click event."
  attr :id, :string, required: true
  attr :count, :integer, required: true
  attr :rest, :global, include: ~w(phx-click phx-value-tag)

  def bw_counter(assigns) do
    ~H"""
    <button id={@id} type="button" class="c-counter" {@rest}>{@count}</button>
    """
  end

  @doc "Inline toggle — strikethrough when off, accent when on."
  attr :pressed, :boolean, default: false
  attr :rest, :global, include: ~w(phx-click phx-value-tag)
  slot :inner_block, required: true

  def bw_toggle(assigns) do
    ~H"""
    <button type="button" class="c-toggle" aria-pressed={to_string(@pressed)} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  # ─── Forms ────────────────────────────────────────────────────────

  @doc "Field wrapper — label, hint, error text. Use with `bw_input`/`bw_textarea`/`bw_select`."
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
  attr :rest, :global, include: ~w(autocomplete autofocus disabled minlength maxlength pattern readonly required)

  def bw_input(assigns) do
    assigns = field_to_attrs(assigns)

    ~H"""
    <%= if @prefix do %>
      <div class="c-input-group">
        <span class="c-input-group__prefix">{@prefix}</span>
        <input
          class="c-input"
          type={@type}
          name={@name}
          id={@id}
          value={@value}
          placeholder={@placeholder}
          aria-invalid={if @invalid, do: "true"}
          {@rest}
        />
      </div>
    <% else %>
      <input
        class="c-input"
        type={@type}
        name={@name}
        id={@id}
        value={@value}
        placeholder={@placeholder}
        aria-invalid={if @invalid, do: "true"}
        {@rest}
      />
    <% end %>
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
      aria-invalid={if @invalid, do: "true"}
      {@rest}
    >{@value}</textarea>
    """
  end

  @doc "Native select wrapped in CUBE chrome. `options` is `[{label, value}]` or just `[value]`."
  attr :name, :string, default: nil
  attr :id, :string, default: nil
  attr :value, :string, default: nil
  attr :options, :list, default: []
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :rest, :global, include: ~w(disabled required)

  def bw_select(assigns) do
    assigns = field_to_attrs(assigns)

    ~H"""
    <select class="c-select" name={@name} id={@id} {@rest}>
      <option :for={opt <- @options} value={option_value(opt)} selected={option_value(opt) == @value}>
        {option_label(opt)}
      </option>
    </select>
    """
  end

  @doc "Custom checkbox — invisible native input + accessible focus ring."
  attr :name, :string, default: nil
  attr :id, :string, default: nil
  attr :value, :string, default: "true"
  attr :checked, :boolean, default: false
  attr :field, Phoenix.HTML.FormField, default: nil
  slot :inner_block, required: true

  def bw_check(assigns) do
    assigns = field_to_attrs(assigns)

    ~H"""
    <label class="c-check">
      <input type="checkbox" name={@name} id={@id} value={@value} checked={@checked} />
      <span class="c-check__box"></span>
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc "Custom radio button — same chrome as `bw_check` with a round indicator."
  attr :name, :string, required: true
  attr :id, :string, default: nil
  attr :value, :string, required: true
  attr :checked, :boolean, default: false
  slot :inner_block, required: true

  def bw_radio(assigns) do
    ~H"""
    <label class="c-check c-check--radio">
      <input type="radio" name={@name} id={@id} value={@value} checked={@checked} />
      <span class="c-check__box"></span>
      {render_slot(@inner_block)}
    </label>
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

  defp option_value({_label, value}), do: value
  defp option_value(value), do: value

  defp option_label({label, _value}), do: label
  defp option_label(value), do: value
end
