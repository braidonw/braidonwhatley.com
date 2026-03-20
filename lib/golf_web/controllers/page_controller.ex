defmodule GolfWeb.PageController do
  use GolfWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
