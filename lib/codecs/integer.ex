defmodule Stamp.Codecs.Integer do
  @moduledoc """
  The codec puts integer ID in string form, removing the need
  for conversion.
  """
  @behaviour Stamp.Codec

  @impl true
  def encode(value), do: to_string(value)

  @impl true
  def decode!(value), do: String.to_integer(value)

  @impl true
  def decode(value) do
    {:ok, decode!(value)}
  rescue
    ArgumentError -> :error
  end
end
