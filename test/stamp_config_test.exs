defmodule Stamp.StampConfigTest do
  use ExUnit.Case, async: true

  @node_num 12

  def node_num(), do: @node_num

  def get_partition(), do: 0

  describe "Stamp.Config.new()" do
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
             } = Stamp.Config.new(params)
    end

    test "raises without node fun" do
      assert_raise ArgumentError, fn -> Stamp.Config.new() end
    end

    test "raises with node fun and 0 node bits" do
      assert_raise ArgumentError, fn -> Stamp.Config.new(node_bits: 0, node_fun: &node_num/0) end
    end

    test "raises without partition fun" do
      assert_raise ArgumentError, fn ->
        Stamp.Config.new(partition_bits: 2, node_bits: 7, node_fun: &node_num/0)
      end
    end

    test "raises with partition fun and 0 part bits" do
      assert_raise ArgumentError, fn ->
        Stamp.Config.new(partition_fun: &get_partition/0, node_fun: &node_num/0)
      end
    end

    test "raises with prefix and without codec" do
      assert_raise ArgumentError, fn -> Stamp.Config.new(prefix: "f", node_fun: &node_num/0) end
    end

    test "raises with invalid zero bits" do
      assert_raise ArgumentError, fn ->
        Stamp.Config.new(time_bits: 0, node_fun: &node_num/0)
      end

      assert_raise ArgumentError, fn ->
        Stamp.Config.new(sequence_bits: 0, node_fun: &node_num/0)
      end
    end

    test "raises with invalid bits" do
      params = [
        partition_bits: 4,
        time_bits: 41,
        node_bits: 4,
        sequence_bits: 13,
        partition_fun: &get_partition/0,
        node_fun: &node_num/0
      ]

      assert_raise ArgumentError, fn -> Stamp.Config.new(params) end
    end
  end
end
