integer_config =
  Stamp.Config.new(
    node_bits: 0,
    sequence_bits: 22
  )

prefixed_config =
  Stamp.Config.new(
    node_bits: 0,
    sequence_bits: 22,
    prefix: "foo_",
    codec: Stamp.Codecs.Base62
  )

Benchee.run(
  %{
    "Generate integer stamps" => fn ->
      for _ <- 1..1_000_000 do
        Stamp.next_id(:myfield, integer_config)
      end
    end,
    "Generate stamps with prefix and base62 encoding" => fn ->
      for _ <- 1..1_000_000 do
        Stamp.next_id(:myfield, prefixed_config)
      end
    end,
  },
  formatters: [{Benchee.Formatters.Console, extended_statistics: true}],
  time: 10
)
