defmodule Stamp.Codec do
  @moduledoc """
  Stamp codec behaviour.

  Modules implementing this behaviour can work as Stamp codecs, converting between
  integer and string versions of stamps.
  """
  @callback encode(integer) :: binary()

  @callback decode!(String.t()) :: integer() | :no_return

  @callback decode(String.t()) :: {:ok, integer()} | :error
end
