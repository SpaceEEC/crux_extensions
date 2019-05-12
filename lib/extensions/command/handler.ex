defmodule Crux.Extensions.Command.Handler do
  @moduledoc """
    Handler module serving as entry point for command pipelines.

    ## Example

    ```elixir
    defmodule MyBot.Handler do
      use Crux.Extensions.Command.Handler

      def commands() do
        [
          MyBot.Command.Ping,
          MyBot.Command.Dog
        ]
      end
      def producers(), do: MyBot.Producers.fetch()
      def rest(), do: MyBot.Rest
      def prefixes(), do: ["!"]
    end
    ```
  """

  alias Crux.Extensions.Command
  alias Crux.Structs.Message

  defmacro __using__(_ \\ []) do
    quote location: :keep do
      @doc false
      def start_link(arg), do: Crux.Extensions.Command.Supervisor.start_link(__MODULE__, arg)
      @doc false
      def child_spec(arg), do: Crux.Extensions.Command.Supervisor.child_spec(__MODULE__, arg)

      @doc """
        The default `c:#{unquote(__MODULE__)}.respond/1` implementation, sending a
        message with the in `Command.t()` defined `response` to the defined `response_channel`.
      """
      @spec respond(Command.t()) :: Message.t() | no_return()
      def respond(command) do
        unquote(__MODULE__).respond(command, __MODULE__)
      end

      @doc """
        The default `c:#{unquote(__MODULE__)}.handle_prefixes/1` implementation, fetching
        all prefixes from `c:#{unquote(__MODULE__)}.prefix/0` and try to slice them off.
      """
      @spec handle_prefixes(message :: Message.t()) :: [{:ok, String.t()} | :error]
      def handle_prefixes(message) do
        unquote(__MODULE__).handle_prefixes(message, __MODULE__)
      end

      @doc """
        TThe default `c:#{unquote(__MODULE__)}.match_commands/3` implementation, fetching
        all commands from `c:#{unquote(__MODULE__)}.commands/0` and comparing their triggers
        with the beginning of `content`.

        `content` is the string `c:#{unquote(__MODULE__)}.handle_prefixes/1` returned.
      """
      @spec match_commands(
              content :: String.t(),
              Message.t(),
              shard_id :: non_neg_integer()
            ) :: [{Command.command_info(), Command.t()}]
      def match_commands(content, message, shard_id) do
        unquote(__MODULE__).match_commands(content, message, shard_id, __MODULE__)
      end
    end
  end

  ### Required Callbacks

  @doc """
    Gets all available commands.
  """
  @callback commands() :: [Command.command()]

  @doc """
    Gets the current producers.
  """
  @callback producers() :: [pid()]

  @doc """
    Gets the module handling rest.

    > See `Crux.Rest`
  """
  @callback rest() :: module()

  @doc """
    Gets the current prefixes.

    > `nil` is used for "no prefix"
  """
  @callback prefixes() :: [String.t() | nil]

  ### Optional callbacks

  @doc """
    Called when an error occured.

    > Not implementing this function causes any errors to terminate the handling process.
  """
  @callback on_error(Command.t(), todo :: any()) :: any()

  @doc """
    Called after the command is done to send the response.
  """
  @callback respond(Command.t()) :: any()

  @doc """
    Removes the prefix from content.

    Returns a list of:
    - `{:ok, content}` if a prefix matched
    - `:error` if a prefix did not
  """
  @callback handle_prefixes(message :: Message.t()) :: [{:ok, String.t()} | :error]

  @doc """
    Gets all commands matching the given content.
  """
  @callback match_commands(
              content :: String.t(),
              message :: Message.t(),
              shard_id :: non_neg_integer()
            ) :: [{Command.command_info(), Command.t()}]

  @optional_callbacks respond: 1, handle_prefixes: 1, match_commands: 3

  ### Functions always here

  @doc false
  # Handles incoming events, extracting content, matching commands, running them, and handling errors if necessary.
  @spec handle_event(Crux.Base.Consumer.event(), module()) :: any()
  def handle_event({_, message, shard_id}, module) do
    for {:ok, content} <- module.handle_prefixes(message),
        {command_info, command} <-
          module.match_commands(content, message, shard_id) do
      command =
        if function_exported?(module, :on_error, 3) do
          try do
            run_command(command_info, command)
          rescue
            e ->
              module.on_error(command, e, __STACKTRACE__)

              nil
          end
        else
          run_command(command_info, command)
        end

      if command do
        module.respond(command)
      end
    end
  end

  @doc false
  # Executes a command, including all required commands (and their required commands).
  @spec run_command(Command.command(), Command.t()) :: Command.t()
  def run_command(_command, %Command{halted: true} = command), do: command

  def run_command(command_mod, %Command{} = command) when is_atom(command_mod) do
    run_command({command_mod, []}, command)
  end

  def run_command({command_mod, command_arg}, %Command{} = command) do
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

  ### Default implementation for optional callbacks

  @doc false
  # Responds with a message if requested.
  @spec respond(Command.t(), module()) :: Message.t() | nil | no_return()
  def respond(%Command{response: response, response_channel: response_channel}, _module)
      when is_nil(response)
      when is_nil(response_channel) do
    nil
  end

  def respond(%Command{response: response, response_channel: response_channel}, module) do
    module.rest().create_message!(response_channel, response)
  end

  @doc false
  # Trims the prefixes off the message's content.
  @spec handle_prefixes(Message.t(), module()) :: [{:ok, String.t()} | :error]
  def handle_prefixes(%Message{content: content}, module) do
    prefixes = module.prefixes()

    Enum.map(prefixes, &handle_prefix(content, &1))
  end

  @doc false
  # Matches commands given the content and returns a list of command infos and `Command.t()`s.
  @spec match_commands(
          content :: String.t(),
          Message.t(),
          shard_id :: non_neg_integer(),
          module()
        ) :: [{Command.command_info(), Command.t()}]
  def match_commands(content, message, shard_id, module) do
    [command | args] = String.split(content, ~r{ +})

    command = String.downcase(command)

    command_infos =
      Enum.map(
        module.commands(),
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

  ### Helpers

  # Slices the prefix off the content and returns {:ok, rest}, if not possible, returns :error.
  @spec handle_prefix(content :: String.t(), prefix :: String.t() | nil) ::
          {:ok, String.t()} | :error
  defp handle_prefix(content, nil), do: {:ok, content}

  defp handle_prefix(content, prefix) do
    content_down = String.downcase(content)

    if String.starts_with?(content_down, prefix) do
      content = String.slice(content, String.length(prefix)..-1)

      {:ok, content}
    else
      :error
    end
  end
end
