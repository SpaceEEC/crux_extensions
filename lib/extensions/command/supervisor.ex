defmodule Crux.Extensions.Command.Supervisor do
  @moduledoc false

  use ConsumerSupervisor

  alias Crux.Extensions.Command.Consumer

  def start_link(args) do
    opts = init_opts(args)
    ConsumerSupervisor.start_link(__MODULE__, opts)
  end

  defp init_opts(args) do
    prefix =
      case args do
        %{prefix: prefix} when not is_nil(prefix) ->
          String.downcase(prefix)

        _ ->
          nil
      end

    command_infos =
      Enum.map(
        args.commands,
        fn
          {_command, _arg} = command_info -> command_info
          command when is_atom(command) -> {command, []}
        end
      )

    %{producers: producers, rest: rest} = args

    %{
      prefix: prefix,
      command_infos: command_infos,
      producers: producers,
      rest: rest
    }
  end

  def init(%{producers: producers} = opts) do
    children = [Consumer.child_spec(opts)]
    opts = [strategy: :one_for_one, subscribe_to: producers.()]

    ConsumerSupervisor.init(children, opts)
  end
end
