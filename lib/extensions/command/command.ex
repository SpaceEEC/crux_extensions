defmodule Crux.Extensions.Command do
  @moduledoc ~S"""
    Behaviour module used to compose command pipelines.

  ## Examples

  ### A Simple Ping Command
    ```elixir
    defmodule MyBot.Command.Ping do
      use Crux.Extensions.Command

      def triggers(), do: ["ping"]

      def call(command, _opts) do
        set_response(command, content: "Pong!")
      end
    end
    ```

  ### A Simple Middleware Command
    ```elixir
    defmodule MyBot.Middleware.FetchPicture do
      use Crux.Extensions.Command

      def call(command, opts) do
        # Default the type to :cat
        type = Keyword.get(opts, :type, :cat)

        case MyBot.Api.fetch_picture(type) do
          {:ok, picture} ->
            assign(command, :picture, picture)
          {:error, _error} ->
            command
            |> set_response(content: "An error occurred while fetching the picture.")
            # Halt the pipeline to stop any further execution of commands or middlewares
            |> halt()
        end
      end
    end
    ```

  ### Using the Middleware Command
    ```elixir
    defmodule MyBot.Command.Dog do
      use Crux.Extensions.Command

      def triggers(), do: ["dog"]

      # Specify the type of :dog
      def required(), do: [{MyBot.Middleware.FetchPicture, type: :dog}]

      def call(command, _opts) do
        set_response(command, content: "Your dog picture link: #{command.assigns.picture}")
      end
    end
    ```
  """

  defstruct assigns: %{},
            trigger: nil,
            args: [],
            message: nil,
            shard_id: nil,
            halted: false,
            response: nil,
            response_channel: nil

  @typedoc """
    Represents the current state of an executing command.
  """
  @type t :: %__MODULE__{
          assigns: %{atom() => term()},
          trigger: String.t(),
          args: [String.t()],
          message: Crux.Structs.Message.t(),
          shard_id: non_neg_integer(),
          halted: boolean(),
          response: term(),
          response_channel: Crux.Rest.Util.channel_id_resolvable()
        }

  @typedoc """
    A module implementing the `Crux.Extensions.Command` behaviour.
  """
  @type command_mod :: module()

  @typedoc """
    Options being passed to the `c:call/2` of a `t:command_mod/0`.

    The exact type is defined by the command itself.
  """
  @type command_opts :: term()

  @typedoc """
    A command module, or command module and options tuple.
  """
  @type command :: command_mod() | {command_mod(), command_opts()}

  defmacro __using__(_ \\ []) do
    quote do
      @behaviour Crux.Extensions.Command

      import Crux.Extensions.Command
    end
  end

  @doc """
    Sets the response content for this command.
  """
  @spec set_response(t(), term()) :: t()
  def set_response(%__MODULE__{} = command, response) do
    %{command | response: response}
  end

  @doc """
    Sets the response channel for this command.
  """
  @spec set_response_channel(t(), Crux.Rest.Util.channel_id_resolvable() | nil) :: t()
  def set_response_channel(%__MODULE__{} = command, response_channel) do
    response_channel =
      unless response_channel == nil, do: Crux.Rest.Util.resolve_channel_id(response_channel)

    %{command | response_channel: response_channel}
  end

  @doc """
    Halts this command, no other commands will be executed fater this one.
  """
  @spec halt(t()) :: t()
  def halt(%__MODULE__{} = command) do
    %{command | halted: true}
  end

  @doc """
    Assigns an arbitrary value to an atom key, which is accessible
    under the `assigns` field of a `Command`.
  """
  @spec assign(t(), key :: atom(), value :: term()) :: t()
  def assign(%__MODULE__{assigns: assigns} = command, key, value) when is_atom(key) do
    %{command | assigns: Map.put(assigns, key, value)}
  end

  @doc """
    Returns a list of required command modules to run before this one.
  """
  @callback required() :: [command_mod() | {command_mod(), command_opts()}]

  @doc """
    Exeucting this command module.
  """
  @callback call(t(), command_opts()) :: t()

  @doc """
    List of possible triggers for this command module.

    Only used and required for primarily handled commands.
  """
  @callback triggers() :: [String.t() | nil]

  @optional_callbacks required: 0, triggers: 0
end
