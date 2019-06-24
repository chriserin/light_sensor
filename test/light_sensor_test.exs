defmodule LightSensor.Data do
  def data do
    1..100
    |> Enum.map(fn n ->
      {Enum.random(0..n), Enum.random(0..100)}
    end)
  end
end

defmodule LightSensorTest do
  use ExUnit.Case

  setup do
    {:ok, message_broker_pid} = MessageBroker.start_link()
    {:ok, _pid} = MockLightSensor.start_link(message_broker_pid, self())
    {:ok, pid} = LightServer.start_link(message_broker_pid)
    [light_server_pid: pid]
  end

  test "Does Light Server receive messages?" do
    MockLightSensor.start_messages()
    assert_receive(:ended, 10000)
    assert nineties = LightServer.get_nineties()
    assert(length(nineties) > 0)
  end
end

defmodule LightServer do
  use GenServer
  @name __MODULE__

  @impl true
  def init(args) do
    {:ok, args}
  end

  def start_link(broker) do
    {:ok, pid} = GenServer.start_link(__MODULE__, %{nineties: []}, name: @name)
    GenServer.cast(broker, {:subscribe, pid})
    {:ok, pid}
  end

  def get_nineties do
    GenServer.call(@name, :get_nineties)
  end

  @impl true
  def handle_cast({:light, light_amount}, %{nineties: amounts}) when light_amount > 90 do
    {:noreply, %{nineties: [light_amount | amounts]}}
  end

  @impl true
  def handle_cast({:light, _light_amount}, state) do
    # do nothing
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_nineties, _from, %{nineties: amounts} = state) do
    {:reply, amounts, state}
  end
end

defmodule MockLightSensor do
  use GenServer

  @name __MODULE__

  @impl true
  def init(args) do
    {:ok, args}
  end

  def start_link(message_broker_pid, start_end_notifier_pid) do
    result =
      {:ok, _pid} =
      GenServer.start_link(
        __MODULE__,
        %{
          message_broker: message_broker_pid,
          start_end_notifier: start_end_notifier_pid,
          data: LightSensor.Data.data()
        },
        name: @name
      )

    result
  end

  def start_messages() do
    GenServer.cast(@name, :next)
  end

  @impl true
  def handle_info(:next, state) do
    GenServer.cast(@name, :next)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:next, %{
        message_broker: broker,
        start_end_notifier: start_end_notifier_pid,
        data: [{next_light_message, _} | []]
      }) do
    GenServer.cast(broker, {:light_message, next_light_message})
    send(start_end_notifier_pid, :ended)
    {:noreply, %{}}
  end

  @impl true
  def handle_cast(:next, %{
        message_broker: broker,
        start_end_notifier: start_end_notifier_pid,
        data: [{interval, next_light_message} | rest]
      }) do
    send(start_end_notifier_pid, :started)
    Process.send_after(self(), :next, interval)
    GenServer.cast(broker, {:light_message, next_light_message})
    {:noreply, %{message_broker: broker, start_end_notifier: start_end_notifier_pid, data: rest}}
  end
end

defmodule MessageBroker do
  use GenServer

  @name __MODULE__

  @impl true
  def init(args) do
    {:ok, args}
  end

  def start_link() do
    GenServer.start_link(@name, %{subscriptions: []})
  end

  @impl true
  def handle_cast({:subscribe, pid}, %{subscriptions: subs}) do
    {:noreply, %{subscriptions: [pid | subs]}}
  end

  @impl true
  def handle_cast({:light_message, message}, %{subscriptions: subs}) do
    Enum.each(subs, fn sub_pid ->
      GenServer.cast(sub_pid, {:light, message})
    end)

    {:noreply, %{subscriptions: subs}}
  end
end
