defmodule PantheonWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PantheonWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="flex items-center justify-between px-4 sm:px-6 lg:px-8 py-3 border-b border-slate-800">
      <div class="flex-1">
        <nav class="flex items-center gap-4">
          <.link
            navigate="/"
            class="text-sm font-semibold hover:opacity-80 transition"
          >
            Pantheon
          </.link>
          <ul class="flex items-center gap-1">
            <li>
              <.link
                navigate="/"
                class="px-3 py-1.5 text-sm font-medium rounded-lg transition-colors text-slate-400 hover:text-white hover:bg-slate-800"
              >
                Settings
              </.link>
            </li>
            <li>
              <.link
                navigate="/metrics"
                class="px-3 py-1.5 text-sm font-medium rounded-lg transition-colors text-slate-400 hover:text-white hover:bg-slate-800"
              >
                Metrics
              </.link>
            </li>
          </ul>
        </nav>
      </div>
      <div class="flex-none">
        <ul class="flex items-center gap-4">
          <%= if @current_scope do %>
            <li>
              <span class="text-sm text-slate-500 truncate max-w-48 hidden sm:inline">
                {@current_scope.email}
              </span>
            </li>
            <li>
              <.link
                navigate="/auth/logout"
                class="inline-flex items-center gap-2 px-3 py-1.5 text-sm font-medium rounded-lg hover:bg-slate-800 transition-colors"
              >
                Logout
              </.link>
            </li>
          <% else %>
            <li>
              <a
                href="/auth/login"
                class="inline-flex items-center gap-2 px-3 py-1.5 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-500 transition-colors"
              >
                Sign in
              </a>
            </li>
          <% end %>
        </ul>
      </div>
    </header>

    <main class="px-4 py-8 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-5xl">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
end
