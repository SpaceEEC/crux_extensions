defmodule Crux.Extensions.Command.Consumer do
  @moduledoc false

  alias Crux.Extensions.Command

  @type command_info :: {Command.command_mod(), Command.command_opts()}
  @type command_infos :: [command_info()]

  @doc """
    Starts a consumer task handling a CREATE_MESSAGE event.
  """
  @spec start_link(Command.options(), Crux.Base.Processor.event()) :: {:ok, pid()} | :ignore
  def start_link(opts, {:MESSAGE_CREATE, _, _} = event) do
    Task.start_link(__MODULE__, :handle_event, [opts, event])
  end

  # Not a MESSAGE_CREATE event, therefore not a command, therefore ignore it
  def start_link(_, _), do: :ignore

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  @doc """
    Handles incoming CREATE_MESSAGE events, executing possible commands.
  """
  def handle_event(opts, {_, %{content: content} = message, shard_id}) do
    case handle_prefix(opts.prefix, content) do
      {:ok, content} ->
        for {command_mod, command} <- match_commands(opts, content, message, shard_id) do
          command = run_command(command_mod, command)

          if command.response && command.response_channel do
            command.rest.create_message!(
              command.response_channel,
              command.response
            )
          end
        end

      _ ->
        nil
    end
  end

  ### Command (matching)

  @doc """
    Removes the prefix, if not nil, from content and returns an `{:ok, content}` tuple.
    Returns `:error` if prefix did not match.
  """
  @spec handle_prefix(
          prefix :: String.t() | nil,
          content :: String.t()
        ) :: {:ok, String.t()} | :error
  def handle_prefix(nil, content), do: {:ok, content}

  def handle_prefix(prefix, content) do
    content_down = String.downcase(content)

    if String.starts_with?(content_down, prefix) do
      content = String.slice(content, String.length(prefix)..-1)

      {:ok, content}
    else
      :error
    end
  end

  @doc """
    Gets all commands matching the given content.
  """
  @spec match_commands(
          opts :: Command.options(),
          content :: String.t(),
          message :: Crux.Structs.Message.t(),
          shard_id :: non_neg_integer()
        ) :: [{Command.command_info(), Command.t()}]
  def match_commands(%{command_infos: command_infos, rest: rest}, content, message, shard_id) do
    [command | args] = String.split(content, ~r{ +})

    command = String.downcase(command)

    for {command_mod, _} = command_info <- command_infos,
        ^command <- command_mod.triggers() do
      {command_info,
       %Command{
         trigger: command,
         args: args,
         message: message,
         shard_id: shard_id,
         rest: rest,
         response_channel: message.channel_id
       }}
    end
  end

  ### Command (running)

  @doc """
    Executes a command, including all required commands (and their required commands).
  """
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
end
