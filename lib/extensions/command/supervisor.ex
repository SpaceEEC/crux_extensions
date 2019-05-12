defmodule Crux.Extensions.Command.Supervisor do
  @moduledoc false

  use ConsumerSupervisor

  alias Crux.Extensions.Command.Consumer

  def child_spec(handler, opts) when is_atom(handler) and is_list(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [handler, opts]},
      type: :supervisor
    }
  end

  @spec start_link(handler :: module(), [GenServer.option()]) :: Supervisor.on_start()
  def start_link(handler, opts) when is_atom(handler) do
    ConsumerSupervisor.start_link(__MODULE__, handler, opts)
  end

  @spec init(handler :: module()) ::
          {:ok, [:supervisor.child_spec()], options :: keyword()} | :ignore
  def init(handler) do
    children = [Consumer.child_spec(handler)]
    opts = [strategy: :one_for_one, subscribe_to: handler.producers()]

    ConsumerSupervisor.init(children, opts)
  end
end
