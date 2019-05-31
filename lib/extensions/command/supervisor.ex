defmodule Crux.Extensions.Command.Supervisor do
  @moduledoc false

  use ConsumerSupervisor

  def child_spec(handler_module, opts)
      when is_atom(handler_module) and is_tuple(opts) and tuple_size(opts) == 2 do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [handler_module, opts]},
      type: :supervisor
    }
  end

  def child_spec(handler_module, opts)
      when is_atom(handler_module) do
    child_spec(handler_module, {opts, []})
  end

  @spec start_link(
          module(),
          {opts :: term(), [GenServer.option()]}
        ) :: Supervisor.on_start()
  def start_link(handler_module, {opts, gen_opts})
      when is_atom(handler_module) do
    ConsumerSupervisor.start_link(__MODULE__, {handler_module, opts}, gen_opts)
  end

  @spec init({handler :: module(), opts :: term()}) ::
          {:ok, [:supervisor.child_spec()], options :: keyword()} | :ignore
  def init({handler, opts})
      when is_atom(handler) do
    children = [
      %{
        id: handler,
        start: {handler, :start_task, [opts]},
        type: :worker,
        restart: :temporary
      }
    ]

    opts = [strategy: :one_for_one, subscribe_to: handler.producers(opts)]

    ConsumerSupervisor.init(children, opts)
  end
end
