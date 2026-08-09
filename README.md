# Stamp

Stamp is a fast and flexible Snowflake-flavored ID generator based on 8-byte
integers with optional encoding.

[The original Snowflake](https://blog.x.com/engineering/en_us/a/2010/announcing-snowflake) supported
BigTech-scale numbers (e.g. 1024 workers each inserting up to 4,096,000 records per second). With
BEAM favoring vertical (rather than horizontal) scaling and hardware getting more powerful every year
it is reasonable to assume that we can leverage the bits in the ID more effectively than Twitter did
back in 2010, especially if the application never reaches Twitter's scale.

## Features

<a href="https://github.com/a3kov/stamp/raw/main/assets/stamp_structure.jpg">
  <img align="right" style="margin-left:16px;" width="300px" src="https://github.com/a3kov/stamp/raw/main/assets/stamp_structure.jpg">
</a>

 - works both with and without Ecto

 - BlazingFast™ sequences on top of process-free atomic counters

 - no global configuration - uses per-field configuration and runtime values

 - user-configurable number of bits for every part of the ID

 - some parts can be disabled, freeing up the bits for other parts

 - optional encoding of the integers to string versions

 - optional Stripe-style prefix to easily distinguish IDs of different models/schemas

 - optional range-based partitioning and sharding (experimental)

<div style="clear: both"></div><br>

## How stamps look

| Type                                    | Stamp                  |
|-----------------------------------------|------------------------|
| Raw, no partitioning                    | `5406450851512320`     |
| Base62                                  | `"Ol6XKJ8oy"`          |
| Base62 + prefix                         | `"u_Ol6XKJ8oy"`        |
| Integer codec (always a string)         | `"5406450851512320"`   |
| Integer + prefix                        | `"u_5406450851512320"` |
| Raw, 256 partitions, p255 (worst case)  | `9187364417633648640`  |
| 256 partitions, p255, Base62            | `"AwgE2gA8mq8"`        | 

## Stamp vs Alternatives

UUID fields have become more popular recently, but they are expensive for use in indexes and
especially primary keys. UUIDv7 improves upon v4 and other versions in some ways, but the size
hasn't changed. There are also exotic alternatives like KSUID and ULID, but they share some
issues of UUID.

|                                             | Stamp                  | Serial/Identity  | UUID         |
|---------------------------------------------|------------------------|------------------|--------------|
| generated in the application                | ✅️                     | ❌️               | ✅️           |
| globally unique with distributed generation | ❌️                     | ❌️               | ✅️           |
| compact in terms of storage and RAM         | ✅️                     | ✅️               | ❌️           |
| composite PK/indexes without bloat          | ✅️                     | ✅️               | ❌️           |
| looks good and is short both raw/encoded    | ✅️                     | ✅️               | ❌️           |
| efficient BTree index operations            | ✅️                     | ✅️               | ✅️ in v7     |
| may remove the need for extra time field    | ✅️                     | ❌️               | ✅️ in v7     |
| bulk inserts                                | ✳️ sequence nuances[1] | ✅️               | ✅️           |
| range partitioning/sharding (not by time)   | ✅️                     | ❌️               | ❌️           |
| keeps creation time secret                  | ❌️                     | ✳️ guessable[2]  | ❌️ not in v7 |
| keeps number of records secret              | ✅️                     | ❌️ barely[3]     | ✅️           |
| next id is unpredictable                    | ✳️ depends[4]          | ❌️               | ✅️           |
| easy to set up and use                      | ❓️ planning, setup[5]  | ✅️               | ✅️           |

[1] If an insert overflows the sequence, time goes into the future. This does not limit the insertion,
    but forces timestamp accuracy trade-offs. In the worst case scenario you can have more accurate
    version of creation time in a separate field. See *Important details and caveats* below for more info.

[2] Because there is only 1 sequence correlated with creation, one could roughly estimate the
    creation time of a record by comparing the number with other records, where the time may
    be known.

[3] Under normal conditions 1 used sequence number corresponds to 1 record. If we can observe
    sequence growth, we can estimate or even know precisely how many records are created in a
    period of time.
    With total number of records it's a bit different. Some applications set initial sequence
    number high to help with the issue, but it's only a half measure. If it's possible to observe
    random ids inside the application, one can notice the gap and guess that it's empty.

[4] Stamp is monotonic for a combination of partition, node number, sequence id. If you can
    generate ids for this combination, you can predict next id. Some randomness can be added
    by randomly picking from a pool of node numbers on each generation. In general, Stamp is
    definitely not as good as UUID in this regard simply because of the size difference.

[5] The library provides good defaults tuned for “average project scale” rather than “Twitter
    scale”, but learning about the available configuration parameters to get the most benefits
    is still encouraged.

## Installation

The package can be installed by adding `stamp` to your list of dependencies in `mix.exs`:
```elixir
def deps do
  [
    {:stamp, "~> 0.1"}
  ]
end
```

## Usage

Stamp structure, once chosen, can be hard or even impossible to change later. There are 2
upfront decisions:

 - Do you want to use partitioning and/or sharding and how many partitions/shards you want ?
   By default it's disabled.

 - How many bits you want to reserve for timestamps ? Default is 41 (like in Snowflake) which
   is enough to store time for ~70 years.

Both of these can't be reversed later without breaking existing identifiers. Everything else in
the ID has no permanent meaning (unless you add one) and only serves as uniqueness source.

A minimal Stamp configuration starts with node function - a function returning node
number.
```elixir
defmodule MyConf do
  def node() do
    # A non-negative integer fitting in node_bits (7 by default), as long as
    # it's unique across all BEAM nodes (and other applications generating 
    # same ids, if you have any). We put a literal here for simplicity, but it's
    # a runtime setting so it must not be compiled-in.
    0
  end
end
```

If using Ecto, add Stamp as a primary/foreign key to schemas.

```elixir
defmodule Post do
  use Ecto.Schema

  @primary_key {:id, Stamp, [.., node_fun: &MyConf.node/0, autogenerate: true]}

  schema "posts" do
    has_many :comments, Comment
  end
end

defmodule Comment do
  use Ecto.Schema

  @primary_key {:id, Stamp, [.., node_fun: &MyConf.node/0, autogenerate: true]}
  @foreign_key_type Stamp

  schema "comments" do
    belongs_to :post, Post
  end
end
```

Then to migrations.
```elixir
defmodule CreatePostsComments do
  use Ecto.Migration

  def change do
    create table(:posts, primary_key: [type: :bigint]) do
      ...
    end

    create table(:comments, primary_key: [type: :bigint]) do
      add :post_id, references(:posts, on_delete: :delete_all), null: false
    end
  end
end
```

Or add to all migrations as the default if you want to go all-in.
```elixir
config :myproject, MyProject.Repo,
  migration_primary_key: [type: :bigint]
```

For description of every Stamp parameter see `Stamp.Config.new/1`.

To generate stamps outside Ecto use `Stamp.next_id/3`.
```elixir
config = Stamp.Config.new(node_fun: &MyConf.node/0)
id = Stamp.next_id(:some_id, config)
```

## Important details and caveats

There are edge cases that must be understood:

 - If OS time is corrected backwards, the last used timestamp is now officially "the future".
   Stamp will keep using the last timestamp while consuming the same sequence until it overflows,
   or until the current time advances past the last used timestamp.

 - When the sequence overflows and time has not advanced past the last used timestamp, Stamp will
   increment the timestamp by 1, even if that means going into the future (this is another case of
   "the future").

 - While “in the future”, Stamp will keep consuming sequences and will advance to the next
   timestamp only on overflow - this can happen multiple times. We can think of it as “ID 
   generation driving the time”, but essentially it is slowing down Stamp’s internal time and
   letting the OS time catch up.

In other words, the time is monotonic within a single node and does not strictly reflect
OS time (which is not monotonic). An NTP daemon (ntpd) must be installed on every server where
the application is deployed to make the generated timestamps more accurate and consistent across
all nodes. Time corrections (including backward ones) are inevitable, but we must keep their 
magnitude manageable so that the timestamps still roughly reflect real time.

Sequence bits must be sufficient for the generation volume (you can either increase the bits or
reduce the volume) if you want to avoid advancing the time too far into the future.
Generation of millions of IDs with exactly the same timestamp may not always be possible.

A sequence is uniquely identified by the combination of sequence_id, node number, and partition
number. If generation is evenly distributed across partitions, reallocating bits from the sequence
to the partition does not reduce the sustainable generation rate (if it wasn’t already obvious).

Stamp has [Telemetry](https://telemetry.hexdocs.pm/readme.html) integration for monitoring of
sequence overflows. In this context there are "normal" overflows (after OS time correction), 
"bad" overflows (a sequence can't keep up with normal volume) or a combination of the two.

```elixir
def handle_event([:stamp, :sequence, :overflow], measurements, metadata, _) do
  %{time: time, last_time: last_time} = measurements
  # Metadata describes specific sequence.
  %{sequence_id: sequence_id, node: node, partition: partition} = metadata
end
```

`time` is the time that Stamp attempted to use initially for the current generation. `last_time`
is the time that was used to generate the previous id. Both of these are "compressed" versions
(after subtracting epoch). You can compare them to roughly understand what's going on, log the
events, build metrics on top, etc. For Ecto fields `sequence_id` is a `{schema, field}` tuple.

## Partitioning and sharding

If a table grows too large, one can split it into parts for more efficient processing, either on
the same server (partitioning) or across different servers (sharding). There are many ways to do
this, but one that is universally applicable to non-historical data is hash-based partitioning.

Let’s say you have a multi-tenant app without DB-level isolation of tenants, and you want to
partition tenant data by the hash of tenant_id. For this to work, the partition key must be part
of every unique index. That means you would need to include tenant_id in all primary keys of the
partitioned tables, and composite primary keys have poor support in Ecto - they work with some
features but not with others.

This library offers another way: we can put partition number in the highest bits of the id, which will
result in splitting the keyspace in equal parts (partitions). This allows us to keep using non-composite
primary keys while enjoing the benefits of partitioning. Using consistent hashing of the tenant_id we
can achieve both resource colocation and even distribution of tenants across partitions (the actual
resource distribution will depend on how uniform the tenants are). And our indexes are much smaller
this way.

But there are also downsides compared to the “partition key in composite PK” option. The database
may not always know where to look for a specific row. This can force it to scan all partitions,
which is expensive (the more partitions, the more expensive). If you have a resource whose
resource.id is range-partitioned by the hash of tenant_id, and you are selecting resources of a
specific tenant, the database doesn’t know which partitions to look in. The good news is that we
can help the database by explicitly adding the range to the WHERE clause, e.g.
`WHERE resource.id BETWEEN A AND B`. This process of removing irrelevant partitions from the query
plan is called *partition pruning*.

If you expect your table to grow very big (tens or even hundreds of millions of rows), it may make sense
to enable partitions in Stamp, even if you are not partitioning the table from the start.
This way later you will be able to partition it with some downtime but without changing the IDs.

The biggest difference after enabling stamp partitioning is that the IDs are not globally k-sorted.
They are only k-sorted within a single partition.

Sharding in this context is not a separate feature - it's simply a byproduct of partitioning. If you
have split the tables in parts, and every part is known to have dedicated range of IDs, you can also
distribute partitions between multiple servers. It can be useful to think of Stamp's partition
number as a logical shard. The exact mapping of shards to the physical locations of records can be
decided separately.

## Benchmarks

The library includes a simple benchmark measuring generation of stamps. On a single core even with
encoding enabled you can generate ~ million stamps per second. The exact numbers will depend on the
CPU and other factors, but the main conclusion is you won't reach id generation bottleneck with
this library (computation-wise).

## License

Copyright 2026 Andrey Tretyakov
The source code of the project is released under Apache License 2.0.
Check LICENSE file for more information.
