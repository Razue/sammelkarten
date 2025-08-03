defmodule SammelkartenWeb.AdminAuth do
  @moduledoc """
  LiveView authentication for admin access.
  """
  import Phoenix.LiveView

  @admin_password Application.compile_env(:sammelkarten, :admin_password, "admin123")

  def on_mount(:ensure_admin, _params, session, socket) do
    if session["admin_password"] == @admin_password do
      {:cont, socket}
    else
      socket = 
        socket
        |> put_flash(:error, "Admin access required. Please login.")
        |> redirect(to: "/admin/login")
      
      {:halt, socket}
    end
  end

  @doc """
  Authenticates user with the given password.
  """
  def authenticate_admin(socket, password) when is_binary(password) do
    if password == @admin_password do
      {:ok, socket}
    else
      {:error, socket}
    end
  end

  @doc """
  Sets admin authentication in the session.
  """
  def login_admin(socket) do
    # This would typically be handled by the LiveView that calls this
    socket
  end

  @doc """
  Removes admin authentication from the session.
  """
  def logout_admin(socket) do
    # This would typically be handled by the LiveView that calls this
    socket
  end
end