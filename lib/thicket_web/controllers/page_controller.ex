defmodule ThicketWeb.PageController do
  use ThicketWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
