defmodule JSON.Decode do

  import String, only: [lstrip: 1, rstrip: 1]

  defexception UnexpectedTokenError, token: nil do
    def message(exception) do
      "Invalid JSON - unexpected token >>#{exception.token}<<"
    end
  end

  defexception UnexpectedEndOfBufferError, message: "Invalid JSON - unexpected end of buffer"

  def from_json(s) when is_binary(s) do
    { result, rest } = consume_value(lstrip(s))
    unless "" == rstrip(rest) do
      raise UnexpectedTokenError, token: rest
    end
    result
  end

  # consume_value: binary -> { nil | true | false | List | HashDict | binary, binary }

  defp consume_value("null"  <> rest), do: { nil,   rest }
  defp consume_value("true"  <> rest), do: { true,  rest }
  defp consume_value("false" <> rest), do: { false, rest }

  defp consume_value(s) when is_binary(s) do
    case s do
      << ?[, rest :: binary >> ->
        consume_array_contents { [], lstrip(rest) }
      << ?{, rest :: binary >> ->
        consume_object_contents { HashDict.new, lstrip(rest) }
      << ?-, m, rest :: binary >> when m in ?0..?9 ->
        { number, rest } = consume_number { m - ?0, rest }
        { -1 * number, rest }
      << m, rest :: binary >> when m in ?0..?9 ->
        consume_number { m - ?0, rest }
      << ?", rest :: binary >> ->
        consume_string { [], rest }
      _ ->
        if String.length(s) == 0 do
          raise UnexpectedEndOfBufferError
        end
        raise UnexpectedTokenError, token: s
    end
  end

  # Array Parsing

  ## consume_array_contents: { List, binary } -> { List, binary }

  defp consume_array_contents { acc, << ?], after_close :: binary >> } do
    { Enum.reverse(acc), after_close }
  end

  defp consume_array_contents { acc, json } do
    { value, after_value } = consume_value(lstrip(json))
    acc = [ value | acc ]
    after_value = lstrip(after_value)

    case after_value do
      << ?,, after_comma :: binary >> ->
        after_comma = lstrip(after_comma)
        consume_array_contents { acc, after_comma }
      << ?], after_close :: binary >> ->
        consume_array_contents { acc, << ?], after_close :: binary >> }
    end
  end

  # Object Parsing

  ## consume_object_contents: { Dict, binary } -> { Dict, binary }

  defp consume_object_contents { acc, << ?}, rest :: binary >> } do
    { acc, rest }
  end

  defp consume_object_contents { acc, << ?", rest :: binary >> } do
    { key, rest } = consume_string { [], rest }

    case lstrip(rest) do
      << ?:, rest :: binary >> ->
        rest = lstrip(rest)
      <<>> ->
        raise UnexpectedEndOfBufferError
      _ ->
        raise UnexpectedTokenError, token: rest
    end

    { value, rest } = consume_value(rest)
    acc = HashDict.put(acc, key, value)
    rest = lstrip(rest)

    case rest do
      << ?,, rest :: binary >> ->
        rest = lstrip(rest)
        consume_object_contents {acc, rest}
      << ?}, rest :: binary >> ->
        consume_object_contents { acc, << ?}, rest :: binary >> }
      <<>> ->
        raise UnexpectedEndOfBufferError
      _ ->
        raise UnexpectedTokenError, token: rest
    end
  end

  defp consume_object_contents { _, "" }  do
    raise UnexpectedEndOfBufferError
  end

  defp consume_object_contents { _, json } do
    raise UnexpectedTokenError, token: json
  end

  # Number Parsing

  ## consume_number: { Number, binary } -> { Number, binary }

  defp consume_number { n, "" } do
    { n, "" }
  end

  defp consume_number { n, << next_char, rest :: binary >> } do
    case next_char do
      x when x in ?0..?9 ->
        consume_number { n * 10 + next_char - ?0, rest }
      ?. ->
        { fractional, tail } = consume_fractional({ 0, rest }, 10.0)
        { n + fractional, tail }
      _ ->
        { n, << next_char, rest :: binary >> }
    end
  end

  defp consume_fractional { n, "" }, _ do
    { n, "" }
  end

  defp consume_fractional { n, << next_char, rest :: binary >> }, power do
    case next_char do
      m when m in ?0..?9 ->
        consume_fractional { n + (next_char - ?0) / power, rest }, power * 10
      _ ->
        { n, << next_char, rest :: binary >> }
    end
  end

  # String Parsing

  ## consume_number: { List, binary } -> { List | binary, binary }

  defp consume_string { _, "" } do
    raise UnexpectedEndOfBufferError
  end

  defp consume_string { acc, json } do
    case json do
      << ?\\, ?f,  rest :: binary >> -> consume_string { [ "\f" | acc ], rest }
      << ?\\, ?n,  rest :: binary >> -> consume_string { [ "\n" | acc ], rest }
      << ?\\, ?r,  rest :: binary >> -> consume_string { [ "\r" | acc ], rest }
      << ?\\, ?t,  rest :: binary >> -> consume_string { [ "\t" | acc ], rest }
      << ?\\, ?",  rest :: binary >> -> consume_string { [ ?"   | acc ], rest }
      << ?\\, ?\\, rest :: binary >> -> consume_string { [ ?\\  | acc ], rest }
      << ?\\, ?/,  rest :: binary >> -> consume_string { [ ?/   | acc ], rest }
      << ?\\, ?u,  rest :: binary >> -> consume_string consume_unicode_escape({ acc, rest })
      << ?",       rest :: binary >> -> { to_binary(Enum.reverse(acc)), rest }
      << c,        rest :: binary >> -> consume_string { [ c | acc ], rest }
    end
  end

  defp consume_unicode_escape { acc, << a, b, c, d, rest :: binary >> } do
    s = << a, b, c, d >>
    unless JSON.Hex.is_hex?(s) do
      raise UnexpectedTokenError, token: s
    end
    { [ << JSON.Hex.to_integer(s) :: utf8 >> | acc ], rest }
  end

end
