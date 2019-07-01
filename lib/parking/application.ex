defmodule Parking.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  @max_gates 4
  @max_spaces 100

  use Application

  def start(_type, _args) do
    # Retrieve the topologies from the config
    topologies = Application.get_env(:libcluster, :topologies)

    # List all child processes to be supervised
    children = [
      {Cluster.Supervisor, [topologies, [name: Parking.ClusterSupervisor]]},
      # Start the endpoint when the application starts
      ParkingWeb.Endpoint,
      # Starts a worker by calling: Parking.Worker.start_link(arg)
      # {Parking.Worker, arg},
      {Horde.Registry, keys: :unique, name: Parking.Registry},
      {Parking.LotSupervisor, [[max_spaces: @max_spaces], [name: Parking.LotSupervisor]]},
      Supervisor.child_spec(
        {Horde.Supervisor, strategy: :one_for_one, name: Parking.GateSupervisor},
        id: :gate_supervisor
      ),
      %{
        id: Parking.HordeConnector,
        restart: :transient,
        start: {
          Task,
          :start_link,
          [
            fn ->
              # Join nodes to distributed Registry
              Horde.Cluster.set_members(Parking.Registry, membership(Parking.Registry, nodes()))

              Horde.Cluster.set_members(
                Parking.GateSupervisor,
                membership(Parking.GateSupervisor, nodes())
              )

              Parking.LotSupervisor.join_neighbourhood(nodes())

              1..@max_gates |> Enum.map(&init_gate/1)
            end
          ]
        }
      }
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Parking.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    ParkingWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp nodes, do: [Node.self()] ++ Node.list()

  defp membership(horde, nodes), do: Enum.map(nodes, fn node -> {horde, node} end)

  defp init_gate(number),
    do: Horde.Supervisor.start_child(Parking.GateSupervisor, {Parking.Gate, number})
end
