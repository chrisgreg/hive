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

        # Add descriptions to Instructor metadata if present
        def field_descriptions do
          unquote(
            Macro.escape(
              schema
              |> List.wrap()
              |> Enum.reduce(%{}, fn {name, _type, opts}, acc ->
                case Keyword.get(opts, :description) do
                  nil -> acc
                  desc -> Map.put(acc, name, desc)
                end
              end)
            )
          )
        end
      end
    end
  end

  defp translate_field({name, type, opts}) do
    # Extract description from opts if present
    {description, cleaned_opts} = Keyword.pop(opts, :description)

    field_ast =
      quote do
        field(unquote(name), unquote(translate_type(type)), unquote(cleaned_opts))
      end

    if description do
      quote do
        Module.put_attribute(
          __MODULE__,
          :field_description,
          {unquote(name), unquote(description)}
        )

        unquote(field_ast)
      end
    else
      field_ast
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
