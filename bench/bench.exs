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
    "Integer stamps" => fn ->
      for _ <- 1..1_000 do
        Stamp.next_id(:myfield1, integer_config)
      end
    end,
    "Stamps with prefix and base62 encoding" => fn ->
      for _ <- 1..1_000 do
        Stamp.next_id(:myfield2, prefixed_config)
      end
    end,
  },
  formatters: [{Benchee.Formatters.Console, extended_statistics: true}],
  print: [configuration: false],
  exclude_outliers: true,
  time: 5
)
