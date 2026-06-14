defmodule AppWeb.HomeLive do
  @moduledoc """
  The home page and the contact gate.

  Contact details are **only rendered once the visitor solves the puzzle** — the
  `:solved` branch of the template — so they never appear in the page source
  before the gate is beaten. All game state lives here on the server; the board
  is plain click-to-move (no client-side chess).
  """
  use AppWeb, :live_view

  import AppWeb.ChessComponents
  alias App.Chess

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Beat the board", solved: false)
      |> load_puzzle(Chess.first_puzzle())

    {:ok, socket}
  end

  # ─── Events ───────────────────────────────────────────────────────

  @impl true
  def handle_event("square", _params, %{assigns: %{solved: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("square", %{"square" => sq}, socket) do
    %{selected: selected, targets: targets, movable: movable} = socket.assigns

    socket =
      cond do
        selected == sq -> deselect(socket)
        Map.has_key?(targets, sq) -> play(socket, targets[sq])
        MapSet.member?(movable, sq) -> select(socket, sq)
        true -> deselect(socket)
      end

    {:noreply, socket}
  end

  def handle_event("reset", _params, socket) do
    {:noreply, socket |> load_puzzle(socket.assigns.puzzle) |> assign(message: nil)}
  end

  def handle_event("new-puzzle", _params, socket) do
    next = Chess.next_puzzle(socket.assigns.puzzle.id)
    {:noreply, socket |> load_puzzle(next) |> assign(message: nil)}
  end

  # ─── Move handling ────────────────────────────────────────────────

  defp select(socket, sq) do
    assign(socket, selected: sq, targets: Chess.targets_from(socket.assigns.fen, sq))
  end

  defp deselect(socket), do: assign(socket, selected: nil, targets: %{})

  defp play(socket, uci) do
    state = %{
      fen: socket.assigns.fen,
      mate_in: socket.assigns.puzzle.mate_in,
      moves_made: socket.assigns.moves_made
    }

    case Chess.play(state, uci) do
      %{result: :solved} = res ->
        socket
        |> assign(solved: true, status: :checkmate, message: nil)
        |> assign(history: socket.assigns.history ++ res.moves)

      %{result: :continue} = res ->
        socket
        |> deselect()
        |> assign(
          fen: res.fen,
          rows: Chess.board_rows(res.fen),
          movable: Chess.movable_squares(res.fen),
          moves_made: res.moves_made,
          status: res.status,
          message: nil,
          history: socket.assigns.history ++ res.moves
        )

      %{result: :failed, reason: reason} ->
        socket
        |> load_puzzle(socket.assigns.puzzle)
        |> assign(message: failure_message(reason))

      %{result: :illegal} ->
        deselect(socket)
    end
  end

  # ─── State helpers ────────────────────────────────────────────────

  defp load_puzzle(socket, puzzle) do
    assign(socket,
      puzzle: puzzle,
      fen: puzzle.fen,
      rows: Chess.board_rows(puzzle.fen),
      movable: Chess.movable_squares(puzzle.fen),
      selected: nil,
      targets: %{},
      moves_made: 0,
      status: :ongoing,
      history: [],
      message: nil
    )
  end

  defp failure_message(:stalemate), do: "Stalemate — that's a draw, not a win. Board reset."
  defp failure_message(_), do: "Not the mating line. Board reset — try again."

  defp moves_left(puzzle, moves_made), do: puzzle.mate_in - moves_made

  # ─── Render ───────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />

    <div class="b-page">
      <header class="b-head">
        <a class="b-head__brand" href="#top">braidon whatley</a>
        <nav class="b-head__nav">
          <a href="#work">work</a>
          <a href="#about">about</a>
          <a href="#contact">contact</a>
        </nav>
      </header>

      <main id="top" class="b-main">
        <section class="b-hero">
          <p class="b-hero__kicker">software · systems · craft</p>
          <h1 class="b-hero__name">Braidon<br />Whatley</h1>
          <p class="b-hero__role">
            Founding Engineer & Solution Architect in Melbourne, Australia.
            I build small, careful systems — and lead the teams that ship them.
          </p>
        </section>

        <.gate
          solved={@solved}
          puzzle={@puzzle}
          rows={@rows}
          selected={@selected}
          targets={@targets}
          movable={@movable}
          status={@status}
          moves_made={@moves_made}
          history={@history}
          message={@message}
        />

        <section id="about" class="b-section">
          <h2 class="b-section__h"><span class="b-section__num">01</span> about</h2>
          <div class="b-prose">
            <p>
              I'm a results-driven technologist with experience across software engineering,
              solution architecture, and technology leadership — a mix of deep technical skill,
              a habit of coaching teams, and commercial sense.
            </p>
            <p>
              Currently a Founding Engineer at <a href="https://superapi.com.au">SuperAPI</a>,
              building technology from the ground up. Previously I designed and led complex systems
              at Woolworths, Winc ANZ, and NSW Business Chamber.
            </p>
          </div>
        </section>

        <section id="work" class="b-section">
          <h2 class="b-section__h"><span class="b-section__num">02</span> what i do</h2>
          <ul class="b-facts">
            <li>
              <span class="b-facts__k">engineering</span>
              <span class="b-facts__v">
                Production apps, integrations, and tooling in Elixir, Go, Rust, Python, and TypeScript.
              </span>
            </li>
            <li>
              <span class="b-facts__k">architecture</span>
              <span class="b-facts__v">
                Microservice and monolithic systems, event-driven design, cloud across Azure, GCP, and AWS.
              </span>
            </li>
            <li>
              <span class="b-facts__k">leadership</span>
              <span class="b-facts__v">
                PMP-certified, 10+ years. Led 20+ person teams through transformation and delivery.
              </span>
            </li>
          </ul>
        </section>

        <section class="b-section">
          <h2 class="b-section__h"><span class="b-section__num">03</span> highlights</h2>
          <ul class="b-list">
            <li>
              Built the platform for an Australian tourism start-up in Elixir, Phoenix LiveView, and
              PostgreSQL — launching to thousands of users and an international expansion.
            </li>
            <li>
              Led a 20+ person team to deliver a Salesforce marketing platform serving 100,000+
              businesses across Australia.
            </li>
            <li>
              Designed a Go algorithm that identified unique purchasing organisations from disparate
              data — driving 90% of new-business wins for over a year.
            </li>
            <li>
              Delivered $900K+ in annual savings with an automated AP/AR OCR system integrated with SAP.
            </li>
          </ul>
        </section>

        <footer class="b-foot">
          <span>
            shipping at SuperAPI · reading <i>Designing Data-Intensive Applications</i> · Melbourne
          </span>
          <span class="b-foot__mark">— bw</span>
        </footer>
      </main>
    </div>
    """
  end

  # ─── Gate component ───────────────────────────────────────────────

  attr :solved, :boolean, required: true
  attr :puzzle, :map, required: true
  attr :rows, :list, required: true
  attr :selected, :string, default: nil
  attr :targets, :map, default: %{}
  attr :movable, :any, default: %{}
  attr :status, :atom, default: :ongoing
  attr :moves_made, :integer, default: 0
  attr :history, :list, default: []
  attr :message, :string, default: nil

  defp gate(assigns) do
    ~H"""
    <section id="contact" class="b-section">
      <h2 class="b-section__h">
        <span class="b-section__num">04</span>
        contact
        <span class={["c-gate__tag", @solved && "is-open"]}>
          // {if @solved, do: "unlocked", else: "locked"}
        </span>
      </h2>

      <div :if={@solved} class="c-gate c-gate--open">
        <p class="c-gate__win">Checkmate. Nicely played — the gate is yours.</p>
        <p class="c-gate__win-line">{Enum.join(@history, "  ")}</p>
        <ul class="c-gate__contact">
          <li>
            <span class="b-facts__k">email</span>
            <a href="mailto:braidon@braidonwhatley.com">braidon@braidonwhatley.com</a>
          </li>
          <li>
            <span class="b-facts__k">github</span>
            <a href="https://github.com/braidonw">@braidonw</a>
          </li>
          <li>
            <span class="b-facts__k">linkedin</span>
            <a href="https://linkedin.com/in/braidon-whatley-23916574">braidon whatley</a>
          </li>
        </ul>
      </div>

      <div :if={!@solved} class="c-gate">
        <div class="c-gate__prompt">
          <p class="c-gate__lead">
            My contact details are locked. Beat the board to open them —
            this is a forced win, so it's always possible.
          </p>
          <p class="c-gate__puzzle">
            <b>{@puzzle.title}.</b> {@puzzle.blurb}
          </p>
          <p class="c-gate__meta">
            white to move · mate in {@puzzle.mate_in} ·
            <span class="c-gate__left">{moves_left(@puzzle, @moves_made)} move(s) left</span>
          </p>
        </div>

        <.bw_board
          rows={@rows}
          selected={@selected}
          targets={@targets}
          movable={@movable}
        />

        <div class="c-gate__bar">
          <p class="c-gate__status">
            <span :if={@message}>{@message}</span>
            <span :if={!@message && @history != []}>{Enum.join(@history, "  ")}</span>
            <span :if={!@message && @history == []}>Click a white piece, then its destination.</span>
          </p>
          <div class="c-gate__controls">
            <button type="button" class="c-btn" phx-click="reset">reset</button>
            <button type="button" class="c-btn" phx-click="new-puzzle">new puzzle</button>
          </div>
        </div>
      </div>
    </section>
    """
  end
end
