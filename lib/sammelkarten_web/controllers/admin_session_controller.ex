defmodule SammelkartenWeb.AdminSessionController do
  use SammelkartenWeb, :controller

  defp admin_password, do: Application.get_env(:sammelkarten, :admin_password)

  def create(conn, %{"password" => password}) do
    if password == admin_password() do
      conn
      |> put_session(:admin_authenticated, true)
      |> put_flash(:info, "Admin access granted")
      |> redirect(to: ~p"/admin")
    else
      conn
      |> put_flash(:error, "Invalid password. Access denied.")
      |> redirect(to: ~p"/admin/login")
    end
  end

  def delete(conn, _params) do
    conn
    |> delete_session(:admin_authenticated)
    |> put_flash(:info, "Logged out successfully")
    |> redirect(to: ~p"/cards")
  end
end
