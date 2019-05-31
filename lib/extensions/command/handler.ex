defmodule Crux.Extensions.Handler do
  @moduledoc """
    Handler module serving as entry point for command pipelines.

  ## Example

    ```elixir
    defmodule MyBot.Handler do
      use Crux.Extensions.Command.Handler

      def commands(_opts) do
        [
          MyBot.Command.Ping,
          MyBot.Command.Dog
        ]
      end
      def producers(_opts), do: MyBot.Producers.fetch()
      def rest(_opts), do: MyBot.Rest
      def prefixes(_opts), do: ["!"]
    end
    ```
  """
  alias Crux.Base.Processor
  alias Crux.Structs.Message

  alias Crux.Extensions.Command
  alias Crux.Extensions.Command.Supervisor

  @typedoc """
    Custom options provided by the developer.
  """
  @type opts :: term()

  @doc """
    Gets the current producers.
  """
  @callback producers(opts()) :: [pid()]
  @doc """
    Matches an event, returning a message, shard id tuple on success, or :error on error.
  """
  @callback match_event(
              opts(),
              event :: Processor.event()
            ) :: {:ok, {Message.t(), shard_id :: non_neg_integer()}} | :error

  @doc """
    Gets the current prefixes
  """
  @callback prefixes(opts) :: [String.t() | nil]
  @doc """
    Matches prefixes, slicing them off the message' content and returning an :ok, content tuple, otherwise :error
  """
  @callback match_prefixes(
              opts(),
              message :: Message.t()
            ) :: [{:ok, String.t()} | :error]

  @doc """
    Gets all available commands.
  """
  @callback commands(opts()) :: [Command.command()]
  @doc """
    Matches all command given the content.
  """
  @callback match_commands(
              opts(),
              content :: String.t(),
              message :: Message.t(),
              shard_id :: non_neg_integer()
            ) :: [{Command.command_info(), Command.t()}]

  @doc """
    Gets the module handling rest.

    > See `Crux.Rest`
  """
  @callback rest(opts()) :: module()
  @doc """
    Called after the command is done to send the response.
  """
  @callback respond(opts(), Command.t()) :: any()

  @doc """
    Called when an error occured.

    > Not implementing this function causes any errors to terminate the handling process.
  """
  @callback on_error(
              opts(),
              Command.t(),
              todo :: any()
            ) :: any()

  @optional_callbacks match_event: 2,
                      match_prefixes: 2,
                      match_commands: 4,
                      respond: 2,
                      on_error: 3

  defmacro __using__(_opts \\ []) do
    quote location: :keep do
      @behaviour unquote(__MODULE__)

      ### Default and static behavior
      @doc false
      def start_link(arg), do: Supervisor.start_link(__MODULE__, arg)
      @doc false
      def child_spec(arg), do: Supervisor.child_spec(__MODULE__, arg)

      @doc false
      def start_task(opts, event) do
        with {:ok, data} <- match_event(opts, event) do
          Task.start_link(unquote(__MODULE__), :handle_event, [__MODULE__, opts, data])
        else
          _ ->
            :ignore
        end
      end

      ### Overridables
      @doc "Default implementation matching only MESSAGE_CREATE events"
      defdelegate match_event(opts, event), to: unquote(__MODULE__)

      @doc "Default implementation using `prefixes/1` and stripping them off the beginning of the message."
      def match_prefixes(opts, message),
        do: unquote(__MODULE__).match_prefixes(__MODULE__, opts, message)

      @doc "Default implementation splitting arguments by spaces."
      def match_commands(opts, content, message, shard_id),
        do: unquote(__MODULE__).match_commands(__MODULE__, opts, content, message, shard_id)

      @doc "Default implementation using `rest/1` and `c:Crux.Rest.create_message!/2`."
      def respond(opts, command), do: unquote(__MODULE__).respond(__MODULE__, opts, command)

      defoverridable handle?: 2, match_prefixes: 2, match_commands: 4, respond: 2
    end
  end

  ### Default and static behavior

  @doc false
  # Handles incoming messages, extracting their content, matching commands, running them, and handling errors if necessary.
  def handle_event(handler_module, opts, {message, shard_id}) do
    for {:ok, content} <- handler_module.match_prefixes(opts, message),
        {command_info, command} <- handler_module.match_commands(opts, content, message, shard_id) do
      command =
        if function_exported?(handler_module, :on_error, 3) do
          try do
            run_command(command_info, command)
          rescue
            e ->
              handler_module.on_error(command, e, __STACKTRACE__)

              nil
          end
        else
          run_command(command_info, command)
        end

      if command do
        handler_module.response(opts, command)
      end
    end
  end

  @doc false
  # Executes a command, including all required commands (and their required commands).
  @spec run_command(Command.command(), Command.t()) :: Command.t()
  defp run_command(_command, %Command{halted: true} = command), do: command

  defp run_command(command_mod, %Command{} = command) when is_atom(command_mod) do
    run_command({command_mod, []}, command)
  end

  defp run_command({command_mod, command_arg}, %Command{} = command) do
    if function_exported?(command_mod, :required, 0) do
      Enum.reduce(command_mod.required(), command, &run_command/2)
    else
      command
    end
    |> case do
      %{halted: true} = command ->
        command

      command ->
        command_mod.call(command, command_arg)
    end
  end

  ### Default and static behavior -- End

  ### Optional Callbacks Default Implementation

  @doc false
  # Matches only MESSAGE_CREATE events
  def match_event(_opts, {:MESSAGE_CREATE, message, shard_id}) do
    {:ok, {message, shard_id}}
  end

  def match_event(_opts, _event), do: :error

  @doc false
  # Slices off the prefix(es) from the content
  def match_prefixes(handler_module, opts, %{content: content}) do
    content_down = String.downcase(content)

    opts
    |> handler_module.prefixes()
    |> Enum.map(fn
      nil ->
        {:ok, content}

      prefix ->
        if String.starts_with?(content_down, prefix) do
          content = String.slice(content, String.length(prefix)..-1)

          {:ok, content}
        else
          :error
        end
    end)
  end

  @doc false
  def match_commands(handler_module, opts, content, message, shard_id) do
    [command | args] =
      content
      |> String.trim_leading()
      |> String.split(~r{ +})

    command = String.downcase(command)

    command_infos =
      Enum.map(
        handler_module.commands(opts),
        fn
          {_command_mod, _command_opts} = command_info -> command_info
          command_mod when is_atom(command_mod) -> {command_mod, []}
        end
      )

    for {command_mod, _} = command_info <- command_infos,
        ^command <- command_mod.triggers() do
      {command_info,
       %Command{
         trigger: command,
         args: args,
         message: message,
         shard_id: shard_id,
         response_channel: message.channel_id
       }}
    end
  end

  @doc false
  # Sends a message, if appropriate
  def respond(_handler_module, _opts, %Command{
        response: response,
        response_channel: response_channel
      })
      when is_nil(response)
      when is_nil(response_channel) do
    nil
  end

  def respond(handler_module, opts, %Command{
        response: response,
        response_channel: response_channel
      }) do
    handler_module.rest(opts).create_message!(response_channel, response)
  end

  ### Optional Callbacks Default Implementation -- End
end
