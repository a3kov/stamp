defmodule Stamp.StampConfigTest do
  use ExUnit.Case, async: true

  alias Stamp.Config

  @node_num 12

  def node_num(), do: @node_num

  def get_partition(), do: 0

  describe "Config.new()" do
    test "creates config from params" do
      part_fun = &Stamp.StampConfigTest.get_partition/0
      node_fun = &Stamp.StampConfigTest.node_num/0

      params = [
        partition_bits: 4,
        time_bits: 42,
        node_bits: 4,
        sequence_bits: 13,
        partition_fun: part_fun,
        node_fun: node_fun
      ]

      assert %{
               partition_bits: 4,
               time_bits: 42,
               node_bits: 4,
               sequence_bits: 13,
               partition_fun: ^part_fun,
               node_fun: ^node_fun
             } = Config.new(params)
    end

    test "raises without partition fun" do
      assert_raise ArgumentError, ~r"^partition_fun must be 0-arity function", fn ->
        Config.new(partition_bits: 2, node_bits: 5, node_fun: &node_num/0)
      end
    end

    test "raises with partition fun and invalid part bits" do
      assert_raise ArgumentError, ~r"^partition_bits must be > 0", fn ->
        Config.new(partition_fun: &get_partition/0, node_fun: &node_num/0)
      end

      assert_raise ArgumentError, ~r"^partition_bits must be a non-negative integer", fn ->
        Config.new(
          partition_bits: -1,
          node_bits: 8,
          partition_fun: &get_partition/0,
          node_fun: &node_num/0
        )
      end
    end

    test "raises without node fun" do
      assert_raise ArgumentError, ~r"^node_fun must be 0-arity function", fn ->
        Config.new()
      end
    end

    test "raises with node fun and invalid node bits" do
      assert_raise ArgumentError, "node_bits must be > 0 when node_fun is provided", fn ->
        Config.new(node_bits: 0, time_bits: 48, node_fun: &node_num/0)
      end

      assert_raise ArgumentError, ~r"^node_bits must be a non-negative integer", fn ->
        Config.new(node_bits: -1, time_bits: 49, node_fun: &node_num/0)
      end
    end

    test "raises with invalid bits" do
      assert_raise ArgumentError, ~r"^time_bits must be a positive integer", fn ->
        Config.new(time_bits: 0, node_fun: &node_num/0)
      end

      assert_raise ArgumentError, ~r"^time_bits must be a positive integer", fn ->
        Config.new(time_bits: -1, node_bits: 8, node_fun: &node_num/0)
      end

      assert_raise ArgumentError, ~r"^sequence_bits must be a positive integer", fn ->
        Config.new(sequence_bits: 0, node_fun: &node_num/0)
      end

      assert_raise ArgumentError, ~r"^sequence_bits must be a positive integer", fn ->
        Config.new(sequence_bits: -1, node_bits: 8, node_fun: &node_num/0)
      end
    end

    test "raises with invalid sum of bits" do
      params = [
        partition_bits: 4,
        time_bits: 41,
        node_bits: 4,
        sequence_bits: 13,
        partition_fun: &get_partition/0,
        node_fun: &node_num/0
      ]

      assert_raise ArgumentError, ~r"^Sum of all bit parameters must be", fn ->
        Config.new(params)
      end
    end

    test "raises with invalid epoch" do
      assert_raise ArgumentError, ~r"^epoch must be a positive integer", fn ->
        Config.new(epoch: 0, node_fun: &node_num/0)
      end

      assert_raise ArgumentError, ~r"^epoch must be a positive integer", fn ->
        Config.new(epoch: -1, node_fun: &node_num/0)
      end
    end

    test "raises with prefix and without codec" do
      assert_raise ArgumentError, "codec is required when prefix is enabled", fn ->
        Config.new(prefix: "f", node_fun: &node_num/0)
      end
    end

    test "raises with invalid prefix" do
      assert_raise ArgumentError, "prefix must be a string", fn ->
        Config.new(prefix: 1, codec: Stamp.Codecs.Base62, node_fun: &node_num/0)
      end
    end

    test "raises with invalid codec" do
      assert_raise ArgumentError,
                   "codec must be a module implementing Stamp.Codec behaviour",
                   fn ->
                     Config.new(codec: "codec", node_fun: &node_num/0)
                   end

      assert_raise ArgumentError,
                   "codec must be a module implementing Stamp.Codec behaviour",
                   fn ->
                     Config.new(codec: Stamp.Codec, node_fun: &node_num/0)
                   end

      assert_raise ArgumentError,
                   "could not load module :nonexisting due to reason :nofile",
                   fn ->
                     Config.new(codec: :nonexisting, node_fun: &node_num/0)
                   end
    end
  end
end
