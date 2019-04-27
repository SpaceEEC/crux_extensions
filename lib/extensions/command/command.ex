defmodule Crux.Extensions.Command do
  # state
  defstruct assigns: %{},
            trigger: nil,
            args: [],
            message: nil,
            shard_id: nil,
            halted: false

  # TODO:
  # error handler ?

  # set_response(_channel) ?
  # before (send) handler ?
  # after (send) handler ?
  # -> Requires knowledge of a way to respond

  defmacro __using__(_ \\ []) do
    quote do
      @behaviour Crux.Extensions.Command

      import Crux.Extensions.Command
    end
  end

  @type t :: %__MODULE__{}

  @spec halt(t()) :: t()
  def halt(%__MODULE__{} = command) do
    %{command | halted: true}
  end

  @spec assign(t(), key :: atom(), value :: term()) :: t()
  def assign(%__MODULE__{assigns: assigns} = command, key, value) when is_atom(key) do
    %{command | assigns: Map.put(assigns, key, value)}
  end

  @type command_mod :: module()
  @type command_info :: term()

  @callback required() :: [command_mod() | {command_mod(), command_info()}]

  @callback call(t(), command_info()) :: t()

  @callback triggers() :: [String.t()]

  @optional_callbacks required: 0, triggers: 0
end
