defmodule Musicbox.Player do
  use GenServer
  require Logger
  alias Paracusia.MpdClient

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def play, do: GenServer.cast(__MODULE__, {:play})
  def pause, do: GenServer.cast(__MODULE__, {:pause})
  def toggle, do: GenServer.cast(__MODULE__, {:toggle})
  def status, do: GenServer.call(__MODULE__, {:status})
  def subscribe(pid), do: GenServer.cast(__MODULE__, {:subscribe, pid})
  def next, do: GenServer.cast(__MODULE__, {:next})
  def previous, do: GenServer.cast(__MODULE__, {:previous})
  def play_playlist(m3u), do: GenServer.cast(__MODULE__, {:play_playlist, m3u})
  def play_queue_index(ix), do: GenServer.cast(__MODULE__, {:play_queue_index, ix})
  def update_database, do: GenServer.cast(__MODULE__, {:update_database})
  def add_to_playlist(playlist, song), do: GenServer.cast(__MODULE__, {:add_to_playlist, playlist, song})
  def list_songs, do: GenServer.call(__MODULE__, {:list_songs})
  def list_playlists, do: GenServer.call(__MODULE__, {:list_playlists})
  def shuffle, do: GenServer.cast(__MODULE__, {:shuffle})
  def create_playlist(name), do: GenServer.call(__MODULE__, {:create_playlist, name})
  def volume_up(step \\ 5), do: GenServer.call(__MODULE__, {:volume_up, step})
  def volume_down(step \\ 5), do: GenServer.call(__MODULE__, {:volume_down, step})
  def volume, do: GenServer.call(__MODULE__, {:current_volume})
  def volume(level), do: GenServer.call(__MODULE__, {:set_volume, level})

  @impl true
  def init(_state) do
    Paracusia.PlayerState.subscribe(self())

    # Fetch the current status from MPD as the initial player status
    state = put_player_status(%{}, fetch_player_status())

    {:ok, state}
  end

  @impl true
  def handle_cast({:play}, state) do
    MpdClient.Playback.play()

    {:noreply, state}
  end

  @impl true
  def handle_cast({:pause}, state) do
    MpdClient.Playback.pause(true)
    {:noreply, state}
  end

  def handle_cast({:previous}, state) do
    MpdClient.Playback.previous()
    {:noreply, state}
  end

  def handle_cast({:next}, state) do
    MpdClient.Playback.next()
    {:noreply, state}
  end

  def handle_cast({:toggle}, state) do
    {:ok, %{state: pstate}} = MpdClient.Status.status()

    case pstate do
      :play -> pause()
      :pause -> play()
      :stop -> play()
      _ -> play()
    end

    {:noreply, state}
  end

  def handle_cast({:shuffle}, state) do
    {:ok, %{random: shuffle}} = MpdClient.Status.status()

    Paracusia.MpdClient.Playback.random(!shuffle)

    {:noreply, state}
  end

  def handle_cast({:subscribe, pid}, state) do
    Paracusia.PlayerState.subscribe(pid)

    {:noreply, state}
  end

  def handle_cast({:play_playlist, playlist}, state) do
    MpdClient.Queue.clear()
    MpdClient.Playlists.load(playlist)
    MpdClient.Playback.play_pos(0)

    {:noreply, state}
  end

  def handle_cast({:update_database}, state) do
    MpdClient.Database.update

    {:noreply, state}
  end

  def handle_cast({:add_to_playlist, playlist, song}, state) do
    Logger.debug("Adding #{song} to playlist #{playlist}")
    MpdClient.Playlists.add(playlist, song)

    {:noreply, state}
  end

  def handle_call({:create_playlist, name}, _from, state) do
    # Seems the only way to create a blank playlist is to save one and then clear it.
    # `save` saves the current queue into a playlist, so we have to clear it.
    :ok = MpdClient.Playlists.save(name)
    :ok = MpdClient.Playlists.clear(name)
    info = MpdClient.Playlists.list_info(name)

    {:reply, info, state}
  end

  def handle_call({:current_volume}, _from, state) do
    {:reply, current_volume(), state}
  end

  def handle_call({:volume_up, step}, _from, state) do
    {:reply, change_volume(step), state}
  end

  def handle_call({:volume_down, step}, _from, state) do
    {:reply, change_volume(-step), state}
  end

  def handle_call({:set_volume, level}, _from, state) do
    {:reply, set_volume(level), state}
  end

  @impl true
  def handle_call({:status}, _from, %{player_status: status} = state) do
    {:reply, status, state}
  end

  def handle_call({:list_playlists}, _from, state) do
    {:reply, get_playlists(), state}
  end

  def handle_call({:list_songs}, _from, state) do
    {:reply, get_all_songs(), state}
  end

  @doc """
  In the initialiser we use `Paracusia.PlayerState.subscribe/1` to
  register this server as an event receiver. This handles player state
  change events.

  We don't really care what the event is, only that we should refresh the status
  """
  @impl true
  def handle_info({:paracusia, _message}, state) do
    {:noreply, put_player_status(state, fetch_player_status())}
  end

  defp put_player_status(state, player_status) do
    Map.put(state, :player_status, player_status)
  end

  defp fetch_player_status do
    {:ok, status} = MpdClient.Status.status()
    {:ok, current_song} = MpdClient.Status.current_song()
    {:ok, queue} = MpdClient.Queue.songs_info()

    %{
      status: status,
      queue: queue,
      current_song: current_song,
      playlists: get_playlists()
    }
  end

  defp change_volume(step) do
    set_volume(current_volume() + step)
  end

  defp set_volume(vol) when vol > 100, do: set_volume(100)
  defp set_volume(vol) when vol < 0, do: set_volume(0)
  defp set_volume(vol) do
    MpdClient.Playback.set_volume(vol)
    current_volume()
  end

  defp current_volume do
    {:ok, %{volume: vol}} = MpdClient.Status.status
    vol
  end

  defp get_playlist_songs(id) do
    {:ok, songs} = MpdClient.Playlists.list_info(id)
    songs
  end

  defp get_playlists do
    {:ok, playlists} = MpdClient.Playlists.list_all()

    playlists
    |> Enum.map(fn item ->
      id = item["playlist"]
      songs = get_playlist_songs(id)

      duration =
        songs
        |> Enum.map(fn song -> song["Time"] |> Integer.parse() |> elem(0) end)
        |> Enum.sum()

      %{
        id: id,
        song_count: Enum.count(songs),
        duration: duration,
        songs: get_playlist_songs(id)
      }
    end)
  end

  defp get_all_songs do
    {:ok, songs} = MpdClient.Database.list_all_info

    songs
    |> Enum.map(fn item ->
      filename = item["file"]
      duration = duration(item["duration"])
      playlists = get_playlist_from_song(filename)

      %{
        title: item["Title"],
        album: item["Album"],
        artist: item["Artist"],
        duration: duration,
        year: item["Date"],
        filename: item["file"],
        is_on_playlist: !Enum.empty?(playlists),
        playlists: playlists |> Enum.map_join(",", fn item -> item["playlist"] end)
      }
    end)
  end

  defp get_playlist_from_song(filename) do
    {:ok, playlists} = MpdClient.Playlists.list_all

    playlists
    |> Enum.filter(fn item ->
      playlist_name = item["playlist"]
      {:ok, song_list} = MpdClient.Playlists.list(playlist_name)

      search_song_on_playlist(song_list, filename)
    end)
  end

  defp search_song_on_playlist(song_list, song) do
    song_list
    |> Enum.any?(fn item -> song == item end)
  end

  defp duration(seconds) when is_binary(seconds) do
    {seconds, _} = Integer.parse(seconds)
    duration(seconds)
  end

  defp duration(seconds) do
    minutes = (seconds / 60)
    minutes = minutes |> floor
    seconds = seconds - minutes * 60
    "#{minutes}:#{format_seconds(seconds)}"
  end

  defp format_seconds(seconds) when seconds < 60 do
    :io_lib.format("~2..0B", [seconds]) |> to_string
  end
end