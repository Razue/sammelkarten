defmodule SammelkartenWeb.Plugs.AdminAuth do
  @moduledoc """
  Plug for authenticating admin access with password.
  """
  import Plug.Conn
  import Phoenix.Controller

  defp admin_password, do: Application.get_env(:sammelkarten, :admin_password)

  def init(opts), do: opts

  def call(conn, _opts) do
    password = get_session(conn, :admin_password)

    if password == admin_password() do
      # User is authenticated
      conn
    else
      # User is not authenticated, redirect to login
      conn
      |> put_flash(:error, "Admin access required")
      |> redirect(to: "/admin/login")
      |> halt()
    end
  end

  @doc """
  Authenticates user with the given password.
  Returns {:ok, conn} if successful, {:error, conn} if failed.
  """
  def authenticate(conn, password) when is_binary(password) do
    if password == admin_password() do
      conn = put_session(conn, :admin_password, password)
      {:ok, conn}
    else
      {:error, conn}
    end
  end

  @doc """
  Logs out the admin user by clearing the session.
  """
  def logout(conn) do
    delete_session(conn, :admin_password)
  end

  @doc """
  Checks if the current user is authenticated as admin.
  """
  def authenticated?(conn) do
    get_session(conn, :admin_password) == admin_password()
  end
end
