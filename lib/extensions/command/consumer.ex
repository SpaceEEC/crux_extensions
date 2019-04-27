defmodule Crux.Extensions.Command.Consumer do
  alias Crux.Extensions.Command

  # command_mod = module()
  # command_arg = list()

  # command_info = {command_mod, command_arg}
  # command_infos = [command_info]

  def start_link(command_infos, prefix, event) do
    Task.start_link(__MODULE__, :handle_event, [command_infos, prefix, event])
  end

  def child_spec({command_infos, prefix}) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [command_infos, prefix]},
      restart: :transient
    }
  end

  ### Prefix

  def handle_event(command_infos, nil, {:MESSAGE_CREATE, %{content: content}, _shard_id} = event) do
    handle_possible_command(command_infos, content, event)
  end

  def handle_event(
        command_infos,
        prefix,
        {:MESSAGE_CREATE, %{content: content}, _shard_id} = event
      ) do
    content_down = String.downcase(content)

    if String.starts_with?(content_down, prefix) do
      rest = String.slice(content, String.length(prefix)..-1)

      handle_possible_command(command_infos, rest, event)
    end
  end

  def handle_event(_command_infos, _prefix, _event), do: nil

  ### Command (matching)

  def handle_possible_command(command_infos, content, {_, message, shard_id}) do
    for {command_mod, command} <- match_commands(command_infos, content, message, shard_id) do
      run_command(command_mod, command)
    end
  end

  def match_commands(command_infos, content, message, shard_id) do
    [command | args] = String.split(content, ~r{ +})

    command = String.downcase(command)

    for {command_mod, _} = command_info <- command_infos,
        ^command <- command_mod.triggers() do
      {command_info,
       %Command{
         trigger: command,
         args: args,
         message: message,
         shard_id: shard_id
       }}
    end
  end

  ### Command (running)

  def run_command(_command_info, %Command{halted: true} = command), do: command

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
      %{halted: true} ->
        command

      command ->
        command_mod.call(command, command_arg)
    end
  end
end
