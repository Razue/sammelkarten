defmodule SammelkartenWeb.AdminLoginLive do
  use SammelkartenWeb, :live_view

  defp admin_password, do: Application.get_env(:sammelkarten, :admin_password)

  @impl true
  def mount(_params, session, socket) do
    # Check if already authenticated
    if session["admin_password"] == admin_password() do
      {:ok, push_navigate(socket, to: ~p"/admin")}
    else
      socket =
        assign(socket,
          password: "",
          error_message: nil,
          show_password: false
        )

      {:ok, socket}
    end
  end

  @impl true
  def handle_event("validate", %{"password" => password}, socket) do
    {:noreply, assign(socket, password: password, error_message: nil)}
  end

  @impl true
  def handle_event("toggle_password", _params, socket) do
    {:noreply, assign(socket, show_password: !socket.assigns.show_password)}
  end

  @impl true
  def handle_event("go_back", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/cards")}
  end
end
