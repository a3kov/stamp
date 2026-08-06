defmodule Stamp.Ecto do
  @moduledoc false

  alias Stamp.Config

  defmacro __using__(_) do
    if Code.ensure_loaded?(Ecto.ParameterizedType) do
      quote location: :keep do
        use Ecto.ParameterizedType

        @impl true
        def init(opts) do
          %{
            schema: Keyword.fetch!(opts, :schema),
            field: Keyword.fetch!(opts, :field)
          }
          |> maybe_add_config(opts)
        end

        defp maybe_add_config(params, opts) do
          if Keyword.get(opts, :foreign_key) do
            params
          else
            Map.put(params, :config, Config.new(opts))
          end
        end

        @impl true
        def type(_params), do: :integer

        @impl true
        def cast(nil, _params), do: {:ok, nil}
        def cast("", _params), do: {:ok, nil}

        def cast(data, params) do
          case to_integer(data, field_config(params)) do
            {:ok, _} -> {:ok, data}
            _ -> :error
          end
        end

        @impl true
        def load(nil, _loader, _params), do: {:ok, nil}

        def load(int, _loader, params) when is_integer(int) do
          {:ok, maybe_encode_with_prefix(int, field_config(params))}
        end

        def load(string, _loader, params) when is_binary(string) do
          case to_integer(string, field_config(params)) do
            {:ok, _} -> {:ok, string}
            _ -> :error
          end
        end

        @impl true
        def dump(nil, _, _), do: {:ok, nil}

        def dump(string, _dumper, params) when is_binary(string) do
          to_integer(string, field_config(params))
        end

        @impl true
        def autogenerate(%{schema: schema, field: field} = params) do
          next_id({schema, field}, field_config(params))
        end

        @impl true
        def embed_as(_format, _params), do: :self

        @impl true
        def equal?(nil, nil, _params), do: true
        def equal?(nil, _, _params), do: false
        def equal?(_, nil, _params), do: false

        def equal?(a, b, params) do
          config = field_config(params)
          to_integer!(a, config) == to_integer!(b, config)
        end

        @doc """
        Converts the field value to integer. Returns `{:ok, integer_id}` or `:error` if the
        value can't be decoded.

        Arguments:
          - `id` - stamp in integer or string form.

          - `schema` - Ecto schema module.

          - `field` - Ecto schema field atom.
        """
        @spec to_integer(value(), module(), atom()) :: {:ok, non_neg_integer()} | :error
        def to_integer(id, schema, field) when is_atom(schema) and is_atom(field) do
          params = get_stamp_params!(schema, field)
          to_integer(id, field_config(params))
        end

        @doc """
        Converts the field value to integer. Returns integer id or raises if the value can't
        be decoded.

        Arguments:
          - `id` - stamp in integer or string form.

          - `schema` - Ecto schema module.

          - `field` - Ecto schema field atom.
        """
        @spec to_integer!(value(), module(), atom()) :: non_neg_integer() | :no_return
        def to_integer!(id, schema, field) when is_atom(schema) and is_atom(field) do
          params = get_stamp_params!(schema, field)
          to_integer!(id, field_config(params))
        end

        @doc """
        Generates next id for the field. Raises `ArgumentError` on errors.

        Arguments:
          - `schema` - Ecto schema module.

          - `field` - Ecto schema field atom.

          - `opts` - generation options (same options as in `next_id/3`).
        """
        @spec next_field_id(module(), atom(), Keyword.t()) :: value() | :no_return
        def next_field_id(schema, field, opts \\ []) when is_atom(schema) and is_atom(field) do
          case get_stamp_params!(schema, field) do
            %{config: _} = params ->
              next_id({schema, field}, field_config(params), opts)

            _ ->
              raise ArgumentError,
                    "Belongs_to fields should not generate. Use referred field instead"
          end
        end

        @doc """
        Unpacks parameters stored in the field. Raises `ArgumentError` on errors.

        Arguments:
          - `id` - stamp in "loaded" form.

          - `schema` - Ecto schema module.

          - `field` - Ecto schema field atom.
        """
        @spec unpack(value(), module(), atom()) :: Stamp.t() | :no_return
        def unpack(id, schema, field) when is_stamp(id) and is_atom(schema) and is_atom(field) do
          params = get_stamp_params!(schema, field)
          unpack(id, field_config(params))
        end

        @doc """
        Returns partition stored in the field, or nil. Raises `ArgumentError` on errors.

        Arguments:
          - `id` - stamp in "loaded" form.

          - `schema` - Ecto schema module.

          - `field` - Ecto schema field atom.
        """
        @spec partition(value(), module(), atom()) :: non_neg_integer() | nil
        def partition(id, schema, field) when is_stamp(id) do
          params = get_stamp_params!(schema, field)
          partition(id, field_config(params))
        end

        @doc """
        Returns UTC DateTime stored in the field. Raises `ArgumentError` on errors.

        Arguments:
          - `id` - stamp in "loaded" form.

          - `schema` - Ecto schema module.

          - `field` - Ecto schema field atom.
        """
        @spec datetime(value(), module(), atom()) :: DateTime.t() | :no_return
        def datetime(id, schema, field)
            when is_stamp(id) and is_atom(schema) and is_atom(field) do
          params = get_stamp_params!(schema, field)
          datetime(id, field_config(params))
        end

        defp get_stamp_params!(schema, field) do
          case schema.__schema__(:type, field) do
            {:parameterized, {__MODULE__, params}} ->
              params

            _ ->
              raise ArgumentError, "Invalid field"
          end
        end

        defp field_config(%{config: %Config{} = config}), do: config

        defp field_config(%{schema: schema, field: field}) do
          # When used in relationships we want to use the config of the related field.
          %{related: schema, related_key: rel_field} = schema.__schema__(:association, field)
          {:parameterized, {__MODULE__, params}} = schema.__schema__(:type, rel_field)
          # Referred field may be a relation key too.
          field_config(params)
        end
      end
    else
      quote do
      end
    end
  end
end
