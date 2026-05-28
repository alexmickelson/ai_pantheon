defmodule PantheonWeb.PageControllerTest do
  use PantheonWeb.ConnCase

  test "GET /unauthenticated returns 200", %{conn: conn} do
    conn = get(conn, "/unauthenticated")
    assert html_response(conn, 200)
  end
end
