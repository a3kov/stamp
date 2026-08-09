defmodule Stamp.StampTest do
  use ExUnit.Case, async: true

  @node_num 12
  @partition_key :partition_num

  def node_num(), do: @node_num

  def put_partition(id), do: Process.put(@partition_key, id)
  def get_partition(), do: Process.get(@partition_key)
  def delete_partition(), do: Process.delete(@partition_key)

  defmodule Post do
    use Ecto.Schema

    @primary_key {:id, Stamp,
                  [
                    partition_bits: 4,
                    time_bits: 42,
                    node_bits: 4,
                    sequence_bits: 13,
                    partition_fun: &Stamp.StampTest.get_partition/0,
                    node_fun: &Stamp.StampTest.node_num/0,
                    epoch: 1_700_000_000_000,
                    codec: Stamp.Codecs.Base62,
                    prefix: "foobar_"
                  ]}

    schema "posts" do
      field(:invalid, :integer)
    end
  end

  defmodule Comment do
    use Ecto.Schema

    @primary_key {:id, Stamp, [node_fun: &Stamp.StampTest.node_num/0]}
    @foreign_key_type Stamp

    schema "comments" do
      belongs_to(:post, Post)
    end
  end

  def get_field_params(schema, field) do
    {:parameterized, {Stamp, params}} = schema.__schema__(:type, field)
    params
  end

  def uniq_seq(), do: {:seq, :erlang.unique_integer([:positive])}

  describe "Ecto Stamp" do
    test "autogenerate uses post.id field config" do
      part_fun = &Stamp.StampTest.get_partition/0
      node_fun = &Stamp.StampTest.node_num/0
      params = get_field_params(Post, :id)
      put_partition(11)
      id = Stamp.autogenerate(params)

      assert %{
               partition_bits: 4,
               time_bits: 42,
               node_bits: 4,
               sequence_bits: 13,
               partition_fun: ^part_fun,
               node_fun: ^node_fun,
               epoch: 1_700_000_000_000,
               codec: Stamp.Codecs.Base62,
               prefix: "foobar_"
             } = params.config

      assert %Stamp{partition: 11, node: @node_num} = Stamp.unpack(id, Post, :id)
      delete_partition()
    end

    test "next_field_id/3 and unpack/3 use post.id field config" do
      put_partition(11)
      now_ts = System.os_time(:millisecond)
      id = Stamp.next_field_id(Post, :id, time: now_ts)
      assert %{partition: 11, time: ^now_ts, node: 12} = Stamp.unpack(id, Post, :id)
      delete_partition()
    end

    test "next_field_id/3 raises with comment.post_id " do
      put_partition(11)
      assert_raise ArgumentError, fn -> Stamp.next_field_id(Comment, :post_id) end
      delete_partition()
    end

    test "next_field_id/3 raises with unknown fields" do
      put_partition(11)
      assert_raise ArgumentError, fn -> Stamp.next_field_id(Post, :invalid) end
      assert_raise ArgumentError, fn -> Stamp.next_field_id(Post, :missing) end
      delete_partition()
    end

    test "to_integer/3 raises with unknown fields" do
      put_partition(11)
      assert_raise ArgumentError, fn -> Stamp.to_integer("foo", Post, :invalid) end
      assert_raise ArgumentError, fn -> Stamp.to_integer("foo", Post, :missing) end
      delete_partition()
    end

    test "to_integer!/3 raises with unknown fields" do
      put_partition(11)
      assert_raise ArgumentError, fn -> Stamp.to_integer!("foo", Post, :invalid) end
      assert_raise ArgumentError, fn -> Stamp.to_integer!("foo", Post, :missing) end
      delete_partition()
    end

    test "unpack/3 raises with unknown fields" do
      put_partition(11)
      assert_raise ArgumentError, fn -> Stamp.unpack("foo", Post, :invalid) end
      assert_raise ArgumentError, fn -> Stamp.unpack("foo", Post, :missing) end
      delete_partition()
    end

    test "datetime/3 uses post.id field config" do
      put_partition(11)
      now_ts = System.os_time(:millisecond)
      id = Stamp.next_field_id(Post, :id, time: now_ts)
      dt = Stamp.datetime(id, Post, :id)
      assert %DateTime{time_zone: "Etc/UTC"} = dt
      assert DateTime.to_unix(dt, :millisecond) == now_ts
      delete_partition()
    end

    test "datetime/3 raises in with unknown fields" do
      put_partition(11)
      assert_raise ArgumentError, fn -> Stamp.datetime("LLhPp0FtY", Post, :invalid) end
      assert_raise ArgumentError, fn -> Stamp.datetime("LLhPp0FtY", Post, :missing) end
      delete_partition()
    end

    test "partition/3 uses post.id field config" do
      put_partition(11)
      id = Stamp.next_field_id(Post, :id)
      assert 11 == Stamp.partition(id, Post, :id)
      delete_partition()
    end

    test "partition/3 raises in with unknown fields" do
      put_partition(11)
      assert_raise ArgumentError, fn -> Stamp.partition("LLhPp0FtY", Post, :invalid) end
      assert_raise ArgumentError, fn -> Stamp.partition("LLhPp0FtY", Post, :missing) end
      delete_partition()
    end
  end

  describe "Stamp next_id/3" do
    ###########################################################################
    # Partition
    ###########################################################################

    test "uses partition provided by config" do
      put_partition(123)

      config =
        Stamp.Config.new(
          partition_bits: 7,
          node_bits: 0,
          partition_fun: &get_partition/0
        )

      id = Stamp.next_id(uniq_seq(), config)
      assert 123 = Stamp.partition(id, config)
      delete_partition()
    end

    test "uses partition provided by param" do
      put_partition(13)
      config = Stamp.Config.new(partition_bits: 7, node_bits: 0, partition_fun: &get_partition/0)
      id = Stamp.next_id(uniq_seq(), config, partition: 123)
      assert 123 = Stamp.partition(id, config)
      delete_partition()
    end

    test "uses partition number to create unique sequences" do
      sid = uniq_seq()
      config1 = Stamp.Config.new(partition_bits: 7, node_bits: 0, partition_fun: &get_partition/0)
      id1 = Stamp.next_id(sid, config1, partition: 7)
      config2 = Stamp.Config.new(partition_bits: 7, node_bits: 0, partition_fun: &get_partition/0)
      id2 = Stamp.next_id(sid, config2, partition: 8)
      %{partition: 7, sequence: s1} = Stamp.unpack(id1, config1)
      %{partition: 8, sequence: s2} = Stamp.unpack(id2, config2)
      assert s1 == s2
    end

    test "raises when tring to use invalid partition" do
      put_partition(11)

      config =
        Stamp.Config.new(
          partition_bits: 2,
          sequence_bits: 20,
          node_bits: 0,
          partition_fun: &get_partition/0
        )

      assert_raise ArgumentError, ~r"Partition number must be an integer in 0..", fn ->
        Stamp.next_id(uniq_seq(), config)
      end

      delete_partition()
    end

    test "raises when tring to use invalid partition param" do
      put_partition(0)

      config =
        Stamp.Config.new(
          partition_bits: 2,
          sequence_bits: 20,
          node_bits: 0,
          partition_fun: &get_partition/0
        )

      assert_raise ArgumentError, ~r"Partition number must be an integer in 0..", fn ->
        Stamp.next_id(uniq_seq(), config, partition: 11)
      end

      delete_partition()
    end

    ###########################################################################
    # Timestamp
    ###########################################################################

    test "uses time provided by param" do
      config = Stamp.Config.new(epoch: 1, node_fun: &node_num/0)
      id = Stamp.next_id(uniq_seq(), config, time: 12345)
      assert %{time: 12345} = Stamp.unpack(id, config)
    end

    test "raises when provided invalid time param" do
      config = Stamp.Config.new(time_bits: 4, node_bits: 44, epoch: 4, node_fun: &node_num/0)
      assert_raise ArgumentError, fn -> Stamp.next_id(uniq_seq(), config, time: 25) end
      assert_raise ArgumentError, fn -> Stamp.next_id(uniq_seq(), config, time: 3) end
    end

    ###########################################################################
    # Node
    ###########################################################################

    test "uses node number provided by config" do
      config = Stamp.Config.new(node_fun: &node_num/0)
      id = Stamp.next_id(uniq_seq(), config)
      assert %{node: @node_num} = Stamp.unpack(id, config)
    end

    def node_num2(), do: node_num() - 1

    test "uses node number to create unique sequences" do
      sid = uniq_seq()
      cfg1 = Stamp.Config.new(node_fun: &node_num/0)
      cfg2 = Stamp.Config.new(node_fun: &node_num2/0)
      assert %{sequence: 0} = Stamp.next_id(sid, cfg1) |> Stamp.unpack(cfg1)
      assert %{sequence: 0} = Stamp.next_id(sid, cfg2) |> Stamp.unpack(cfg2)
    end

    test "raises when provided invalid node num" do
      config = Stamp.Config.new(node_bits: 2, sequence_bits: 20, node_fun: &node_num/0)
      assert_raise ArgumentError, fn -> Stamp.next_id(uniq_seq(), config) end
    end

    ###########################################################################
    # Sequence
    ###########################################################################

    test "uses separate sequences with different sequence ids" do
      config = Stamp.Config.new(node_fun: &node_num/0)
      id1 = Stamp.next_id(uniq_seq(), config)
      id2 = Stamp.next_id(uniq_seq(), config)
      %{sequence: seq1} = Stamp.unpack(id1, config)
      %{sequence: seq2} = Stamp.unpack(id2, config)
      assert seq1 == seq2
    end

    test "uses same sequence with same sequence id" do
      config = Stamp.Config.new(epoch: 1, node_fun: &node_num/0)
      sid = uniq_seq()
      id1 = Stamp.next_id(sid, config, time: 2)
      id2 = Stamp.next_id(sid, config, time: 2)
      assert %{sequence: 0} = Stamp.unpack(id1, config)
      assert %{sequence: 1} = Stamp.unpack(id2, config)
    end

    test "restarts sequence when time is increased" do
      cfg = Stamp.Config.new(epoch: 1, node_fun: &node_num/0)
      sid = uniq_seq()
      assert %{time: 2, sequence: 0} = Stamp.next_id(sid, cfg, time: 2) |> Stamp.unpack(cfg)
      assert %{time: 2, sequence: 1} = Stamp.next_id(sid, cfg, time: 2) |> Stamp.unpack(cfg)
      assert %{time: 3, sequence: 0} = Stamp.next_id(sid, cfg, time: 3) |> Stamp.unpack(cfg)
    end

    test "keeps timestamp monotonic and consumes sequences until time normalizes" do
      cfg = Stamp.Config.new(epoch: 1, sequence_bits: 2, node_bits: 20, node_fun: &node_num/0)
      sid = uniq_seq()
      Stamp.next_id(sid, cfg, time: 3)
      assert %{time: 3, sequence: 1} = Stamp.next_id(sid, cfg, time: 3) |> Stamp.unpack(cfg)
      assert %{time: 3, sequence: 2} = Stamp.next_id(sid, cfg, time: 2) |> Stamp.unpack(cfg)
      assert %{time: 3, sequence: 3} = Stamp.next_id(sid, cfg, time: 2) |> Stamp.unpack(cfg)
      assert %{time: 4, sequence: 0} = Stamp.next_id(sid, cfg, time: 2) |> Stamp.unpack(cfg)
      assert %{time: 4, sequence: 1} = Stamp.next_id(sid, cfg, time: 3) |> Stamp.unpack(cfg)
      assert %{time: 4, sequence: 2} = Stamp.next_id(sid, cfg, time: 3) |> Stamp.unpack(cfg)
      assert %{time: 4, sequence: 3} = Stamp.next_id(sid, cfg, time: 3) |> Stamp.unpack(cfg)
      assert %{time: 5, sequence: 0} = Stamp.next_id(sid, cfg, time: 4) |> Stamp.unpack(cfg)
      assert %{time: 5, sequence: 1} = Stamp.next_id(sid, cfg, time: 5) |> Stamp.unpack(cfg)
      assert %{time: 6, sequence: 0} = Stamp.next_id(sid, cfg, time: 6) |> Stamp.unpack(cfg)
    end

    test "goes in the future on overflow" do
      cfg = Stamp.Config.new(epoch: 1, sequence_bits: 2, node_bits: 20, node_fun: &node_num/0)
      sid = uniq_seq()
      Stamp.next_id(sid, cfg, time: 2)
      Stamp.next_id(sid, cfg, time: 2)
      Stamp.next_id(sid, cfg, time: 2)
      assert %{time: 2, sequence: 3} = Stamp.next_id(sid, cfg, time: 2) |> Stamp.unpack(cfg)
      assert %{time: 3, sequence: 0} = Stamp.next_id(sid, cfg, time: 2) |> Stamp.unpack(cfg)
      assert %{time: 3, sequence: 1} = Stamp.next_id(sid, cfg, time: 2) |> Stamp.unpack(cfg)
      assert %{time: 4, sequence: 0} = Stamp.next_id(sid, cfg, time: 4) |> Stamp.unpack(cfg)
    end

    def handle_event([:stamp, :sequence, :overflow], measurements, metadata, _) do
      Process.put(:stamp_telemetry, {measurements, metadata})
    end

    test "telemetry called on overflow" do
      :ok =
        :telemetry.attach(
          "stamp-overflow-handler",
          [:stamp, :sequence, :overflow],
          &Stamp.StampTest.handle_event/4,
          nil
        )

      cfg = Stamp.Config.new(epoch: 1, sequence_bits: 2, node_bits: 20, node_fun: &node_num/0)
      sid = uniq_seq()
      Stamp.next_id(sid, cfg, time: 2)
      Stamp.next_id(sid, cfg, time: 2)
      Stamp.next_id(sid, cfg, time: 2)
      Stamp.next_id(sid, cfg, time: 2)
      Stamp.next_id(sid, cfg, time: 2)
      data = Process.get(:stamp_telemetry)
      assert {%{time: 1, last_time: 1}, %{sequence_id: sid, node: 12, partition: nil}} == data
    end

    ###########################################################################
    # Codec/Prefix
    ###########################################################################

    test "uses codec when provided" do
      config = Stamp.Config.new(codec: Stamp.Codecs.Base62, node_fun: &node_num/0)
      id = Stamp.next_id(uniq_seq(), config)
      assert is_binary(id)
      assert %Stamp{} = Stamp.unpack(id, config)
    end

    test "adds prefix when enabled" do
      config =
        Stamp.Config.new(prefix: "foo_", codec: Stamp.Codecs.Integer, node_fun: &node_num/0)

      id = Stamp.next_id(uniq_seq(), config)
      assert "foo_" <> _encoded = id
      assert %Stamp{} = Stamp.unpack(id, config)
    end
  end

  describe "Stamp partition/3" do
    test "returns partition stored in the id" do
      config1 = Stamp.Config.new(partition_bits: 7, node_bits: 0, partition_fun: &get_partition/0)
      config2 = Stamp.Config.new(node_fun: &node_num/0)
      id1 = Stamp.next_id(uniq_seq(), config1, partition: 77)
      id2 = Stamp.next_id(uniq_seq(), config2)
      assert Stamp.partition(id1, config1) == 77
      assert Stamp.partition(id2, config2) == nil
    end

    test "raises ArgumentError with invalid input" do
      config = Stamp.Config.new(codec: Stamp.Codecs.Integer, node_fun: &node_num/0)
      assert_raise ArgumentError, fn -> Stamp.partition(4_632_028_712_534_016, config) end
      assert_raise ArgumentError, fn -> Stamp.partition("LLhPp0FtY", config) end
      config = Stamp.Config.new(node_fun: &node_num/0)
      assert_raise ArgumentError, fn -> Stamp.partition("4632028712534016", config) end
    end
  end

  describe "Stamp datetime/3" do
    test "returns UTC datetime stored in the id" do
      config = Stamp.Config.new(node_fun: &node_num/0)
      now_ts = System.os_time(:millisecond)
      id = Stamp.next_id(uniq_seq(), config, time: now_ts)
      dt = Stamp.datetime(id, config)
      assert %DateTime{time_zone: "Etc/UTC"} = dt
      assert DateTime.to_unix(dt, :millisecond) == now_ts
    end

    test "raises ArgumentError with invalid input" do
      config = Stamp.Config.new(codec: Stamp.Codecs.Integer, node_fun: &node_num/0)
      assert_raise ArgumentError, fn -> Stamp.datetime(4_632_028_712_534_016, config) end
      assert_raise ArgumentError, fn -> Stamp.datetime("LLhPp0FtY", config) end
      config = Stamp.Config.new(node_fun: &node_num/0)
      assert_raise ArgumentError, fn -> Stamp.datetime("4632028712534016", config) end
    end
  end

  describe "Stamp unpack/3" do
    test "unpacks field data w/ partition and node" do
      partition = 1
      compressed_ts = 1013
      node = 3
      sequence = 17

      config =
        Stamp.Config.new(
          partition_bits: 5,
          time_bits: 41,
          node_bits: 7,
          sequence_bits: 10,
          node_fun: &node_num/0,
          partition_fun: &get_partition/0,
          codec: nil,
          prefix: nil,
          epoch: 1000
        )

      <<id::signed-integer-size(64)>> =
        <<
          0::size(1),
          partition::size(config.partition_bits),
          compressed_ts::size(config.time_bits),
          node::size(config.node_bits),
          sequence::size(config.sequence_bits)
        >>

      time = compressed_ts + config.epoch

      assert %Stamp{
               partition: ^partition,
               time: ^time,
               node: ^node,
               sequence: ^sequence
             } = Stamp.unpack(id, config)
    end

    test "unpacks field data w/o partition" do
      compressed_ts = 1013
      node = 3
      sequence = 17

      config =
        Stamp.Config.new(
          partition_bits: 0,
          time_bits: 41,
          node_bits: 12,
          sequence_bits: 10,
          node_fun: &node_num/0,
          codec: nil,
          prefix: nil,
          epoch: 1000
        )

      <<id::signed-integer-size(64)>> =
        <<
          0::size(1),
          compressed_ts::size(config.time_bits),
          node::size(config.node_bits),
          sequence::size(config.sequence_bits)
        >>

      time = compressed_ts + config.epoch

      assert %Stamp{
               partition: nil,
               time: ^time,
               node: ^node,
               sequence: ^sequence
             } = Stamp.unpack(id, config)
    end

    test "unpacks field data w/ partition and w/o node" do
      partition = 1
      compressed_ts = 1013
      sequence = 17

      config =
        Stamp.Config.new(
          partition_bits: 8,
          time_bits: 41,
          node_bits: 0,
          sequence_bits: 14,
          partition_fun: &get_partition/0,
          codec: nil,
          prefix: nil,
          epoch: 1000
        )

      <<id::signed-integer-size(64)>> =
        <<
          0::size(1),
          partition::size(config.partition_bits),
          compressed_ts::size(config.time_bits),
          sequence::size(config.sequence_bits)
        >>

      time = compressed_ts + config.epoch

      assert %Stamp{
               partition: ^partition,
               time: ^time,
               node: nil,
               sequence: ^sequence
             } = Stamp.unpack(id, config)
    end

    test "unpacks field data w/o partition and node" do
      compressed_ts = 1013
      sequence = 17

      config =
        Stamp.Config.new(
          partition_bits: 0,
          time_bits: 45,
          node_bits: 0,
          sequence_bits: 18,
          codec: nil,
          prefix: nil,
          epoch: 1000
        )

      <<id::signed-integer-size(64)>> =
        <<
          0::size(1),
          compressed_ts::size(config.time_bits),
          sequence::size(config.sequence_bits)
        >>

      time = compressed_ts + config.epoch

      assert %Stamp{
               partition: nil,
               time: ^time,
               node: nil,
               sequence: ^sequence
             } = Stamp.unpack(id, config)
    end

    test "raises ArgumentError with invalid input" do
      config = Stamp.Config.new(codec: Stamp.Codecs.Integer, node_fun: &node_num/0)
      assert_raise ArgumentError, fn -> Stamp.unpack(4_632_028_712_534_016, config) end
      assert_raise ArgumentError, fn -> Stamp.unpack("LLhPp0FtY", config) end
      config = Stamp.Config.new(node_fun: &node_num/0)
      assert_raise ArgumentError, fn -> Stamp.unpack("4632028712534016", config) end
    end
  end
end
