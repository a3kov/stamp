defmodule Stamp.Codecs.Base62 do
  @moduledoc """
  Codec using encoding based on alphanumeric characters. Compared to Base64,
  it looks better and is easier to select with a mouse (by double-clicking).
  """
  use BasedIntegers,
    alphabet: ~c"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
end
