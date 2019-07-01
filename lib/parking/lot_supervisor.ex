defmodule Parking.LotSupervisor do
  use Supervisor

  def start_link([args, opts]), do: Supervisor.start_link(__MODULE__, args, opts)

  def init(args) do
    children = [
      # Manages distributed state
      {
        DeltaCrdt,
        sync_interval: 300,
        max_sync_size: :infinite,
        shutdown: 30_000,
        crdt: DeltaCrdt.AWLWWMap,
        name: Parking.Lot.Crdt
      },
      # Interface for tracking state of cars through gates
      {Parking.Lot, args}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  def join_neighbourhood(nodes) do
    # Map all nodes to the CRDT process for that node
    crdts =
      Enum.map(nodes, fn node ->
        :rpc.call(node, Process, :whereis, [Parking.Lot.Crdt])
      end)

    # Creates combinations of all possible node sets in the neighbourhood
    # i.e. for a set [1, 2, 3] -> [{1, [2, 3]}, {2, [1, 3]}, {3, [1, 2]}]
    combos = for crdt <- crdts, do: {crdt, List.delete(crdts, crdt)}

    # Enumerate the list wire up the neighbours
    Enum.each(combos, fn {crdt, crdts} ->
      :ok = DeltaCrdt.set_neighbours(crdt, crdts)
    end)
  end
end
