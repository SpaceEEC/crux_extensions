defmodule Crux.Extensions.Command do
  # state
  defstruct assigns: %{},
            # maybe private?
            message: nil,
            guild: nil,
            # response
            response: nil,
            response_channel: nil,
            halted: false,
            status: nil,
            # hooks
            before_response: [],
            after_response: [],
            after_error: [],
            # TODO
            # References to other libs
            rest: Crux.Rest,
            cache: Crux.Cache.Default

  @type t :: %__MODULE__{}

  @spec set_response_channel(t(), Crux.Rest.Util.channel_id_resolvable()) :: t()
  def set_response_channel(command, response_channel) do
    %{command | response_channel: channel}
  end

  @spec set_response(t(), Crux.Rest.create_message_data()) :: t()
  def set_response(command, response) do
    %{command | response: response}
  end

  @spec halt(t()) :: t()
  def halt(command) do
    %{command | halted: true}
  end

  @spec assign(t(), key :: atom(), value :: term()) :: t()
  def assign(%{assigns: assigns} = command, key, value) when is_atom(key) do
    %{command | assigns: Map.put(assigns, key, value)}
  end

  @spec fetch_guild(t()) :: {:ok, t()} | {:error, :dm | term()}
  def fetch_guild(%{message: %{guild_id: nil}}) do
    {:error, :dm}
  end

  def fetch_guild(%{guild: nil, message: %{guild_id: guild_id}} = command) do
    case command.cache.guild_cache().fetch(guild_id) do
      {:ok, guild} ->
        command = %{command | guild: guild}

        {:ok, command}

      :error ->
        with {:ok, guild} <- command.rest.get_guild(guild_id) do
          command = %{command | guild: guild}

          {:ok, command}
        end
    end
  end

  def fetch_guild(command), do: {:ok, command}

  @spec fetch_member(t()) :: {:ok, t()} | {:error, :dm | term()}
  def fetch_member(%{message: %{guild_id: nil}}), do: {:error, :dm}

  def fetch_member(%{member: nil, message: message} = command) do
    with {:ok, member} <- command.rest.get_guild_member(guild_id, message.author.id) do
      message = %{message | member: member}

      command = %{command | message: message}

      {:ok, {command, member}}
    end
  end

  def fetch_member(command), do: {:ok, command}
end
