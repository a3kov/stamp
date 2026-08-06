defmodule Stamp.Codecs.Base58 do
  @moduledoc """
  Codec using encoding based on alphanumeric alphabet excluding easily
  mistakable characters: 0, O, l, and I. It's commonly used in blockchain
  thanks to its properties.
  """
  use BasedIntegers,
    alphabet: ~c"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
end
