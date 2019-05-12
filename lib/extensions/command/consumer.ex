defmodule Crux.Extensions.Command.Consumer do
  # Module being used as consumer for incoming MESSAGE_CREATE
  # events forwarding them to `Crux.Extensions.Command.Handler`.
  @moduledoc false

  @doc """
    Starts a consumer task handling a CREATE_MESSAGE event.
    Will ignore other events.
  """
  def start_link(handler, {:MESSAGE_CREATE, _message, _shard_id} = event) do
    Task.start_link(Crux.Extensions.Command.Handler, :handle_event, [event, handler])
  end

  # Not a MESSAGE_CREATE event, therefore not a command, therefore ignore it
  def start_link(_handler, {_type, _message, _shard_id}), do: :ignore

  @doc false
  def child_spec(handler) when is_atom(handler) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [handler]},
      restart: :temporary
    }
  end
end
