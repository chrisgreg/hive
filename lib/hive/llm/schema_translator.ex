defmodule Hive.LLM.SchemaTranslator do
  def to_instructor_schema(schema, module_name) do
    # Ensure schema is a list of fields
    fields =
      case schema do
        {_, _, _} = field -> [translate_field(field)]
        fields when is_list(fields) -> Enum.map(fields, &translate_field/1)
      end

    quote do
      defmodule unquote(module_name) do
        use Ecto.Schema
        use Instructor.Validator

        @primary_key false
        embedded_schema do
          (unquote_splicing(fields))
        end
      end
    end
  end

  defp translate_field({name, type, opts}) do
    quote do
      field(unquote(name), unquote(translate_type(type)), unquote(opts))
    end
  end

  defp translate_type(:string), do: :string
  defp translate_type(:integer), do: :integer
  defp translate_type(:float), do: :float
  defp translate_type(:boolean), do: :boolean
  defp translate_type(:map), do: :map
  defp translate_type({:array, type}), do: {:array, translate_type(type)}
  defp translate_type(other), do: other
end
