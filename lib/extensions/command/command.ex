defmodule Crux.Extensions.Command do
  @moduledoc ~S"""
    Behaviour module used to compose command pipelines.

  ## Example

  ### Commands / Middlewares

  #### A Simple Ping Command
    ```elixir
    defmodule MyBot.Command.Ping do
      use Crux.Extensions.Command

      def triggers(), do: ["ping"]

      def call(command, _opts) do
        set_response(command, content: "Pong!")
      end
    end
    ```

  #### A Simple Middleware
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

  #### Using the Middleware
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

  ### Starting `Crux.Extensions.Command`
    ```elixir
    defmodule MyBot.Application do
      use Application

      @commands [MyBot.Command.Ping, MyBot.Command.Dog]

      def start(_, _) do
        children = [
          # Other modules, gateway, rest, etc...
          {Crux.Extensions.Command, %{
            producers: fn -> fetch_producer_pids() end,
            prefix: "!",
            commands: @commands,
            rest: MyBot.Rest
          }}
        ]

        opts = [strategy: :one_for_one]
        Supervisor.start_link(children, opts)
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
            rest: nil,
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
          rest: module(),
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

  @typedoc """
    Available options used to start handling commands.

    Notes:
    * `prefix`: Omitting or `nil` results in commands being triggered without a prefix.
    * `commands`: A list of modules which must implement `c:triggers/0`.
    * `producers`: A function returning the current producers to subsribe to.
    * `rest`: The module (using `Crux.Rest`) which should be used to send a response.
  """
  @type options :: %{
          optional(:prefix) => String.t() | nil,
          commands: [command()],
          producers: (() -> [pid()]),
          rest: module()
        }

  defmacro __using__(_ \\ []) do
    quote do
      @behaviour Crux.Extensions.Command

      import Crux.Extensions.Command, except: [start_link: 1, child_spec: 1]
    end
  end

  # TODO:
  # error handler ?

  # before (send) handler ?
  # after (send) handler ?

  @doc false
  def start_link(arg), do: Crux.Extensions.Command.Supervisor.start_link(arg)
  @doc false
  def child_spec(arg), do: Crux.Extensions.Command.Supervisor.child_spec(arg)

  @spec set_response(t(), term()) :: t()
  def set_response(%__MODULE__{} = command, response) do
    %{command | response: response}
  end

  @spec set_response_channel(t(), Crux.Rest.Util.channel_id_resolvable() | nil) :: t()
  def set_response_channel(%__MODULE__{} = command, response_channel) do
    response_channel =
      unless response_channel == nil, do: Crux.Rest.Util.resolve_channel_id(response_channel)

    %{command | response_channel: response_channel}
  end

  @spec halt(t()) :: t()
  def halt(%__MODULE__{} = command) do
    %{command | halted: true}
  end

  @spec assign(t(), key :: atom(), value :: term()) :: t()
  def assign(%__MODULE__{assigns: assigns} = command, key, value) when is_atom(key) do
    %{command | assigns: Map.put(assigns, key, value)}
  end

  @callback required() :: [command_mod() | {command_mod(), command_opts()}]

  @callback call(t(), command_opts()) :: t()

  @callback triggers() :: [String.t()]

  @optional_callbacks required: 0, triggers: 0
end
