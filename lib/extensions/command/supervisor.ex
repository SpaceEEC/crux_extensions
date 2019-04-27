defmodule Crux.Extensions.Command.Supervisor do
  use ConsumerSupervisor

  alias Crux.Extensions.Command.Consumer

  def start_link(args) do
    ConsumerSupervisor.start_link(__MODULE__, args)
  end

  def init(%{producers: producers, commands: commands, prefix: prefix}) do
    command_infos =
      Enum.map(
        commands,
        fn
          {_command, _arg} = command_info -> command_info
          command when is_atom(command) -> {command, []}
        end
      )

    prefix = String.downcase(prefix)

    children = [Consumer.child_spec({command_infos, prefix})]
    opts = [strategy: :one_for_one, subscribe_to: producers.()]

    ConsumerSupervisor.init(children, opts)
  end
end
