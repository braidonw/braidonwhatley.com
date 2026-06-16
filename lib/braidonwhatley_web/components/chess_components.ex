defmodule AppWeb.ChessComponents do
  @moduledoc """
  Function components for the contact-gate chess puzzle: the board itself and a
  couple of small presentational helpers. Styling lives in the brutalist CUBE
  blocks `c-board` and `c-gate` (`assets/css/styles/blocks/`).
  """
  use Phoenix.Component

  @files ~w(a b c d e f g h)
  @ranks ~w(8 7 6 5 4 3 2 1)

  @doc """
  An 8×8 click-to-move board.

  Squares are buttons that emit a `"square"` event with `phx-value-square`. The
  parent LiveView owns all game logic; this component only paints state:
  `selected` square, `targets` (a `%{to => uci}` map), and `movable` origin
  squares (a `MapSet`). When `disabled`, squares render but don't respond.
  """
  attr :rows, :list, required: true, doc: "8 ranks of cells from `App.Chess.board_rows/1`"
  attr :selected, :string, default: nil
  attr :targets, :map, default: %{}
  attr :movable, :any, default: %{}
  attr :disabled, :boolean, default: false

  def bw_board(assigns) do
    assigns = assign(assigns, files: @files, ranks: @ranks)

    ~H"""
    <div class="c-board" role="grid" aria-label="chess puzzle">
      <div class="c-board__ranks" aria-hidden="true">
        <span :for={r <- @ranks}>{r}</span>
      </div>

      <div class="c-board__grid">
        <button
          :for={cell <- List.flatten(@rows)}
          type="button"
          role="gridcell"
          class={[
            "c-board__sq",
            "is-#{cell.shade}",
            @selected == cell.square && "is-selected",
            Map.has_key?(@targets, cell.square) && "is-target",
            movable?(@movable, cell.square) && "is-movable",
            cell.piece && "has-piece"
          ]}
          disabled={@disabled}
          aria-label={square_label(cell)}
          phx-click="square"
          phx-value-square={cell.square}
        >
          <span :if={cell.piece} class={"c-board__piece is-#{cell.piece.color}"}>
            {cell.piece.glyph}
          </span>
          <span
            :if={Map.has_key?(@targets, cell.square)}
            class="c-board__dot"
            aria-hidden="true"
          >
          </span>
        </button>
      </div>

      <div class="c-board__files" aria-hidden="true">
        <span :for={f <- @files}>{f}</span>
      </div>
    </div>
    """
  end

  defp movable?(%MapSet{} = set, sq), do: MapSet.member?(set, sq)
  defp movable?(_, _), do: false

  defp square_label(%{square: sq, piece: nil}), do: "#{sq}, empty"
  defp square_label(%{square: sq, piece: piece}), do: "#{sq}, #{piece.color} #{piece.type}"
end
