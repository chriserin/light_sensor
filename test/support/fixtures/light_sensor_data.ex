defmodule LightSensor.Data do
  def data do
    1..1000 |> Enum.map(fn n ->
      {Enum.random(0..n), Enum.random(0..100)}
    end
  end
end
