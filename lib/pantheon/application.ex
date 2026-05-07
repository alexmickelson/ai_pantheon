defmodule Pantheon.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        PantheonWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:pantheon, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Pantheon.PubSub}
      ] ++ oidc_children() ++ [PantheonWeb.Endpoint]

    opts = [strategy: :one_for_one, name: Pantheon.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PantheonWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp oidc_children() do
    with {:ok, oidc_config} when oidc_config != [] <- Application.fetch_env(:pantheon, :oidc),
         issuer when is_binary(issuer) <- Keyword.get(oidc_config, :issuer) do
      [
        {Oidcc.ProviderConfiguration.Worker,
         %{
           issuer: issuer,
           name: Pantheon.OidcProvider,
           provider_configuration_opts: %{
             quirks: %{
               document_overrides: %{
                 "pushed_authorization_request_endpoint" => :undefined,
                 "require_pushed_authorization_requests" => false,
                 "token_endpoint_auth_methods_supported" => [
                   "private_key_jwt",
                   "client_secret_basic",
                   "client_secret_post",
                   "tls_client_auth",
                   "client_secret_jwt",
                   "none"
                 ]
               }
             }
           }
         }}
      ]
    else
      _ -> []
    end
  end
end
