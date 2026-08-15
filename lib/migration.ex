defmodule Stamp.Migration do
  @moduledoc """
  Ecto migration tools for Stamp.
  """
  use Ecto.Migration

  alias Stamp.Config

  defmacro __using__(_) do
    quote location: :keep do
      require Stamp.Migration
      import Stamp.Migration
    end
  end

  @doc """
  Create all partitions of a table partitioned by a Stamp field, where
  each partition range corresponds exactly to one Stamp partition number.

  The table must've been partitioned by range based on a Stamp field.
  The resulting DDL is Postgres-specific.

  Arguments:
    - `table` - partitioned table name
    - `partition_bits` - partition bits defining possible partition range
  """
  defmacro pg_create_all_partitions(table, partition_bits) do
    quote bind_quoted: [table: table, partition_bits: partition_bits] do
      for p <- 0..(2 ** partition_bits - 1) do
        Stamp.Migration.pg_create_partition(table, "#{table}_p#{p}", partition_bits, p, p)
      end
    end
  end

  @doc """
  Create partition of a table. The partition may span multiple "virtual partitions"
  represented by partition numbers from `start_pnum` to `end_pnum`, or a single
  partition number (`start_pnum` == `end_pnum`).

  The table must've been partitioned by range based on a Stamp field.
  The resulting DDL is Postgres-specific.

  Arguments:
    - `table` - partitioned table name
    - `partition` - partition table name
    - `partition_bits` - partition bits defining possible partition range
    - `start_pnum` - partition number where partition starts
    - `end_pnum` - partition number where partition ends (inclusive)

  Options:
    - `options` - custom options that will be appended after the generated statement,
      similar to `Ecto.Migration.table/2` `:options`. For example: `TABLESPACE mytablespace`
  """
  defmacro pg_create_partition(table, partition, partition_bits, start_pnum, end_pnum, opts \\ []) do
    quote bind_quoted: [
      table: table,
      partition: partition,
      partition_bits: partition_bits,
      start_pnum: start_pnum,
      end_pnum: end_pnum,
      opts: opts
    ] do
      options = Keyword.get(opts, :options, "")
      {p_start, _} = Config.partition_range(start_pnum, partition_bits)
      p_end =
        if end_pnum == 2 ** partition_bits - 1 do
          "MAXVALUE"
        else
          {_, exc_end} = Config.partition_range(end_pnum, partition_bits)
          exc_end
        end

      execute(
        """
        CREATE TABLE #{partition} PARTITION OF #{table} FOR VALUES FROM (#{p_start}) TO (#{p_end}) #{options}
        """,
        """
        DROP TABLE #{partition}
        """
      )
    end
  end
end
