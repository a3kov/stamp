defmodule Stamp.Config do
  @moduledoc """
  Configuration structure for Stamp. Each stamp is generated and later
  processed according to the configuration parameters.
  """
  @distribute_bits 63
  @default_partition_bits 0
  @default_time_bits 41
  @default_node_bits 7
  @default_sequence_bits 15
  @default_epoch 1_784_842_980_000

  @type t :: %__MODULE__{
          partition_bits: non_neg_integer(),
          time_bits: non_neg_integer(),
          node_bits: non_neg_integer(),
          sequence_bits: pos_integer(),
          partition_fun: fun() | nil,
          node_fun: fun() | nil,
          epoch: pos_integer(),
          codec: atom() | nil,
          prefix: String.t() | nil
        }

  @keys [
    :partition_bits,
    :time_bits,
    :node_bits,
    :sequence_bits,
    :partition_fun,
    :node_fun,
    :epoch,
    :codec,
    :prefix
  ]
  @enforce_keys @keys
  defstruct @keys

  @doc """
  Create new Stamp config from options.
  This function is also used internally to build config at compile time for Ecto IDs.
  Using this function should be preferred over constructing `Stamp.Config` structs manually,
  as it performs validation of the parameters.

  Supported options:
    - `partition_bits` - number of bits reserved for partition number. 0 disables
      partitioning. Default is 0.

    - `time_bits` - positive number of bits reserved for time. Default is
      #{@default_time_bits}.

    - `node_bits` - number of bits reserved for node number. 0 disables per-node-number
      sequences, which can be useful if the generator can't ever require more than 1 node.
      Default is #{@default_node_bits}.

    - `sequence_bits` - positive number of bits reserved for sequence. Default is
      #{@default_sequence_bits}.

    - `node_fun` - 0-arity function returning current node number. The number must be unique
      across all BEAM nodes, and 1 number per BEAM node is enough (although it's not enforced).
      All Stamp configurations can share same node number. The number must fit in `node_bits`
      without overflow. Required with `node_bits` > 0. Default is nil (not set).

    - `partition_fun` - 0-arity function returning current partition. This works as a backchannel
      with `autogenerate: true` PK option in Ecto. Current partition for queries can be
      smuggled in via process dictionary or by other means. When generating IDs directly you can
      instead pass `partition` option to `Stamp.next_field_id/3` and `Stamp.next_id/3`. The
      number must fit in `partition_bits` without overflow. Required with `partition_bits` > 0.
      Default is nil (not set).

    - `epoch` - the number subtracted from the current unix time in milliseconds to
      compress it for storage. For permanently stored data the epoch must be chosen once and
      never changed later. Default is #{@default_epoch}

    - `prefix` - a Stripe-style prefix to add to encoded IDs. For example, setting it to `foo_`
      will generate IDs that look like so: `foo_139546474327455` or `foo_ABdsdDggP`. If set,
      the prefix is always added and expected (values without it will trigger an error).
      Default is nil (disabled).

    - `codec` - a module implementing `Stamp.Codec` behaviour. When set, the library will encode
      the ID after generation/loading, so the final ID will be a string. The encoding must
      maintain lexicographic order for the IDs to have same sorting in string form. Required
      when prefix is set. Default is nil (disabled).
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    partition_bits =
      Keyword.get(opts, :partition_bits, @default_partition_bits)
      |> ensure_non_neg("partition_bits")

    time_bits =
      Keyword.get(opts, :time_bits, @default_time_bits) |> ensure_pos("time_bits")

    node_bits = Keyword.get(opts, :node_bits, @default_node_bits) |> ensure_non_neg("node_bits")

    sequence_bits =
      Keyword.get(opts, :sequence_bits, @default_sequence_bits) |> ensure_pos("sequence_bits")

    epoch = Keyword.get(opts, :epoch, @default_epoch) |> ensure_non_neg("epoch")

    if partition_bits + time_bits + node_bits + sequence_bits != @distribute_bits do
      raise ArgumentError, "Sum of all bit parameters must be #{@distribute_bits}"
    end

    struct(
      __MODULE__,
      %{
        time_bits: time_bits,
        sequence_bits: sequence_bits,
        epoch: epoch
      }
      |> add_partition(partition_bits, opts)
      |> add_node(node_bits, opts)
      |> add_codec_and_prefix(opts)
    )
  end

  defp ensure_non_neg(value, _) when is_integer(value) and value >= 0, do: value
  defp ensure_non_neg(_, name), do: raise(ArgumentError, "#{name} must be a non-negative integer")

  defp ensure_pos(value, _) when is_integer(value) and value > 0, do: value
  defp ensure_pos(_, name), do: raise(ArgumentError, "#{name} must be a positive integer")

  defp add_partition(config, partition_bits, opts) do
    partition_fun = Keyword.get(opts, :partition_fun)

    cond do
      partition_bits > 0 && is_function(partition_fun, 0) ->
        config
        |> Map.put(:partition_bits, partition_bits)
        |> Map.put(:partition_fun, partition_fun)

      partition_bits == 0 && partition_fun ->
        raise ArgumentError, "partition_bits must be > 0 when partition_fun is provided"

      partition_bits == 0 ->
        Map.put(config, :partition_bits, 0)

      true ->
        raise ArgumentError,
              "partition_fun must be 0-arity function and is required when partition_bits > 0"
    end
  end

  defp add_node(config, node_bits, opts) do
    node_fun = Keyword.get(opts, :node_fun)

    cond do
      node_bits > 0 && is_function(node_fun, 0) ->
        config
        |> Map.put(:node_bits, node_bits)
        |> Map.put(:node_fun, node_fun)

      node_bits == 0 && node_fun ->
        raise ArgumentError, "node_bits must be > 0 when node_fun is provided"

      node_bits == 0 ->
        Map.put(config, :node_bits, 0)

      true ->
        raise ArgumentError,
              "node_fun must be 0-arity function and is required when node_bits > 0"
    end
  end

  defp add_codec_and_prefix(config, opts) do
    codec = Keyword.get(opts, :codec)
    prefix = Keyword.get(opts, :prefix)

    cond do
      codec && (!is_atom(codec) || !is_codec?(codec)) ->
        raise ArgumentError, "codec must be a module implementing Stamp.Codec behaviour"

      prefix && !is_binary(prefix) ->
        raise ArgumentError, "prefix must be a string"

      prefix && is_nil(codec) ->
        raise ArgumentError, "codec is required when prefix is enabled"

      true ->
        config
        |> Map.put(:codec, codec)
        |> Map.put(:prefix, prefix)
    end
  end

  defp is_codec?(module) do
    Code.ensure_compiled!(module)
    Code.ensure_loaded?(module)

    function_exported?(module, :encode, 1) &&
      function_exported?(module, :decode, 1) &&
      function_exported?(module, :decode!, 1)
  end
end
