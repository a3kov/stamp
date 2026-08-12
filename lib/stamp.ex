defmodule Stamp do
  @moduledoc """
  Stamp is a fast and flexible Snowflake-flavored ID generator based on 8-byte
  integers with optional encoding.
  """
  import Bitwise
  alias Stamp.Config

  defguardp is_stamp(s) when is_binary(s) or (is_integer(s) and s >= 0)
  use Stamp.Ecto

  @type value :: non_neg_integer() | String.t()

  @type t :: %__MODULE__{
          partition: non_neg_integer() | nil,
          time: non_neg_integer(),
          node: non_neg_integer() | nil,
          sequence: non_neg_integer()
        }

  defstruct partition: nil,
            time: nil,
            node: nil,
            sequence: nil

  @doc """
  Converts the id to integer. Returns `{:ok, integer_id}` or `:error` if the
  value can't be decoded.
  """
  @spec to_integer(value(), Config.t()) :: {:ok, non_neg_integer()} | :error
  def to_integer(value, _) when is_integer(value) and value >= 0, do: {:ok, value}

  def to_integer(value, %Config{codec: codec} = config) when is_binary(value) and codec != nil do
    try do
      maybe_remove_prefix!(value, config) |> codec.decode()
    rescue
      ArgumentError -> :error
    end
  end

  def to_integer(_, _), do: :error

  @doc """
  Converts the id to integer. Returns the integer id or raises if the
  value can't be decoded.

  Arguments:
    - `id` - stamp in integer or string form

    - `config` - `Stamp.Config` structure containing parameters for
      the stamp.
  """
  @spec to_integer!(value(), Config.t()) :: non_neg_integer() | :no_return
  def to_integer!(id, _) when is_integer(id) and id >= 0, do: id

  def to_integer!(id, %Config{codec: codec} = config) when is_binary(id) and codec != nil do
    maybe_remove_prefix!(id, config) |> codec.decode!()
  end

  def to_integer!(_, _), do: raise(ArgumentError, "Invalid value")

  defp maybe_remove_prefix!(string, %{prefix: nil}), do: string

  defp maybe_remove_prefix!(string, %{prefix: prefix}) do
    case string do
      ^prefix <> value -> value
      _ -> raise ArgumentError, "Invalid value"
    end
  end

  defp maybe_encode_with_prefix(int, %Config{} = config) when is_integer(int) do
    case config do
      %{prefix: nil, codec: nil} ->
        int

      %{prefix: nil, codec: codec} ->
        codec.encode(int)

      %{prefix: prefix, codec: codec} ->
        "#{prefix}#{codec.encode(int)}"
    end
  end

  defp normalize!(id, %Config{codec: nil}) when is_integer(id) and id >= 0, do: id

  defp normalize!(id, %Config{codec: codec} = config) when is_binary(id) and codec != nil do
    maybe_remove_prefix!(id, config) |> codec.decode!()
  end

  defp normalize!(_, _), do: raise(ArgumentError, "Invalid value")

  @doc """
  Generates next id using provided sequence_id and configuration.
  This function is for non-Ecto uses. For Ecto fields use `next_field_id/3`.

  Arguments:
    - `sequence_id` - unique term used to create sequence for the stamps.
      Stamps using different `sequence_id` are supposed to be used in
      separate contexts and can have intersecting values without causing
      issues. Do not include config parameters in it - it's done automatically
      by the library. Good examples: `:comment_id`, `{Comment, :id}`.

    - `config` - `Stamp.Config` structure containing parameters for
      generating the ID.

    - `opts` - generation options.

  Supported options:
    - `time` - OS time in milliseconds, using unix epoch. When provided,
      Stamp will try to use it for the generation instead of calling
      `System.os_time/1`. The number must fit in `time_bits` without
      overflow.

    - `partition` - integer number of the partition that will be used instead
      of calling `partition_fun/0` from the config, if the partitioning
      is enabled. The number must fit in `partition_bits` without overflow.
  """
  @spec next_id(any(), Config.t(), Keyword.t()) :: value() | :no_return
  def next_id(sequence_id, %Config{} = config, opts \\ []) do
    partition = get_partition(config, opts)
    node = get_node(config)
    new_ts = get_time(config, opts)
    pt_key = pt_key(sequence_id, node, partition)

    case :persistent_term.get(pt_key, :new_sequence) do
      :new_sequence ->
        seq_ref = :atomics.new(1, signed: false)
        new_ts = get_time(config, opts)
        :atomics.put(seq_ref, 1, pack_time_sequence(new_ts, 0, config))

        try do
          :persistent_term.put_new(pt_key, seq_ref)
          pack_id(partition, new_ts, node, 0, config) |> maybe_encode_with_prefix(config)
        rescue
          ArgumentError -> next_id(sequence_id, config, opts)
        end

      ref ->
        atomic = :atomics.get(ref, 1)
        {prev_ts, prev_seq} = unpack_time_sequence(atomic, config)
        increased_ts? = new_ts > prev_ts
        last_seq? = prev_seq == 2 ** config.sequence_bits - 1
        new_seq = if increased_ts? || last_seq?, do: 0, else: prev_seq + 1

        new_ts =
          cond do
            increased_ts? ->
              new_ts

            last_seq? ->
              :telemetry.execute(
                [:stamp, :sequence, :overflow],
                %{time: new_ts, last_time: prev_ts},
                %{sequence_id: sequence_id, node: node, partition: partition}
              )

              prev_ts + 1

            true ->
              prev_ts
          end

        new_atomic = pack_time_sequence(new_ts, new_seq, config)

        case :atomics.compare_exchange(ref, 1, atomic, new_atomic) do
          :ok ->
            pack_id(partition, new_ts, node, new_seq, config)
            |> maybe_encode_with_prefix(config)

          _ ->
            next_id(sequence_id, config, opts)
        end
    end
  end

  defp get_time(%{time_bits: bits, epoch: epoch}, opts) do
    compressed_ts =
      (Keyword.get(opts, :time) || System.os_time(:millisecond)) - epoch

    if compressed_ts < 0 do
      raise ArgumentError, "Negative time after subtracting epoch"
    end

    validate_in_range!(compressed_ts, bits, "time")
  end

  defp get_partition(%{partition_bits: bits, partition_fun: partition_fun}, opts) do
    partition = Keyword.get(opts, :partition)

    cond do
      bits == 0 ->
        if partition do
          raise ArgumentError, "Partition option provided when partition_bits is 0"
        end

      partition ->
        validate_in_range!(partition, bits, "Partition number")

      true ->
        validate_in_range!(partition_fun.(), bits, "Partition number")
    end
  end

  defp get_node(%{node_bits: 0}), do: nil

  defp get_node(%{node_bits: bits, node_fun: node_fun}) do
    validate_in_range!(node_fun.(), bits, "Node number")
  end

  defp validate_in_range!(num, bits, desc) do
    max_num = 2 ** bits - 1

    if is_integer(num) and num >= 0 and num <= max_num do
      num
    else
      raise ArgumentError, "#{desc} must be an integer in 0..#{max_num} range"
    end
  end

  defp pt_key(sequence_id, nil, nil), do: {__MODULE__, sequence_id}
  defp pt_key(sequence_id, node, nil), do: {__MODULE__, sequence_id, node}
  defp pt_key(sequence_id, node, partition), do: {__MODULE__, sequence_id, node, partition}

  defp pack_time_sequence(time, sequence, %{sequence_bits: seq_bits}) do
    time <<< seq_bits ||| sequence
  end

  defp unpack_time_sequence(atomic, %{sequence_bits: seq_bits}) do
    {atomic >>> seq_bits, atomic &&& (1 <<< seq_bits) - 1}
  end

  defp pack_id(partition, time, node, sequence, config) do
    %{node_bits: n_bits, sequence_bits: seq_bits} = config

    maybe_add_partition(partition, config) |||
      time <<< (n_bits + seq_bits) |||
      maybe_add_node(node, config) |||
      sequence
  end

  defp maybe_add_partition(nil, _), do: 0

  defp maybe_add_partition(value, config) do
    %{time_bits: t_bits, node_bits: n_bits, sequence_bits: seq_bits} = config
    value <<< (t_bits + n_bits + seq_bits)
  end

  defp maybe_add_node(_, %{node_bits: 0}), do: 0

  defp maybe_add_node(value, %{sequence_bits: seq_bits}) do
    value <<< seq_bits
  end

  @doc """
  Unpacks parameters stored in the id.
  This function is for non-Ecto uses. For Ecto fields use `unpack/3`.
  Raises `ArgumentError` on errors.

  Arguments:
    - `id` - stamp in integer or string form (strictly according to config)

    - `config` - `Stamp.Config` structure containing parameters for the stamp.
  """
  @spec unpack(value(), Config.t()) :: Stamp.t() | :no_return
  def unpack(id, %Config{} = config) when is_stamp(id) do
    %{
      partition_bits: p_bits,
      time_bits: t_bits,
      node_bits: n_bits,
      sequence_bits: s_bits,
      epoch: epoch
    } = config

    int = normalize!(id, config)
    partition = if p_bits != 0, do: int >>> (t_bits + n_bits + s_bits)
    node = if n_bits != 0, do: int >>> s_bits &&& (1 <<< n_bits) - 1

    %__MODULE__{
      partition: partition,
      node: node,
      sequence: int &&& (1 <<< s_bits) - 1,
      time: epoch + (int >>> (n_bits + s_bits) &&& (1 <<< t_bits) - 1)
    }
  end

  @doc """
  Returns partition stored in the id, or nil if the stamp is not partitioned.
  This function is for non-Ecto uses. For Ecto fields use `partition/3`.
  Raises `ArgumentError` on errors.

  Arguments:
    - `id` - stamp in integer or string form (strictly according to config)

    - `config` - `Stamp.Config` structure containing parameters for the stamp.
  """
  @spec partition(value(), Config.t()) :: non_neg_integer() | nil
  def partition(id, %Config{} = config) when is_stamp(id) do
    int = normalize!(id, config)

    case config do
      %{partition_bits: 0} ->
        nil

      %{time_bits: t_bits, node_bits: n_bits, sequence_bits: s_bits} ->
        int >>> (t_bits + n_bits + s_bits)
    end
  end

  @doc """
  Returns UTC DateTime stored in the id.
  This function is for non-Ecto uses. For Ecto fields use `datetime/3`.
  Raises `ArgumentError` on errors.

  Arguments:
    - `id` - stamp in integer or string form (strictly according to config)

    - `config` - `Stamp.Config` structure containing parameters for the stamp.
  """
  @spec datetime(value(), Config.t()) :: DateTime.t()
  def datetime(id, %Config{} = config) when is_stamp(id) do
    %{time_bits: t_bits, node_bits: n_bits, sequence_bits: s_bits, epoch: epoch} = config
    int = normalize!(id, config)

    (epoch + (int >>> (n_bits + s_bits) &&& (1 <<< t_bits) - 1))
    |> DateTime.from_unix!(:millisecond)
  end
end
