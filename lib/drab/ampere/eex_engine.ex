defmodule Drab.Ampere.EExEngine do
  @moduledoc false

  import Drab.Ampere.Crypto
  use EEx.Engine

  @anno (if :erlang.system_info(:otp_release) >= '19' do
    [generated: true]
  else
    [line: -1]
  end)

  @doc false
  def init(_opts), do: {:safe, ""}

  @doc false
  def handle_body(body), do: Phoenix.HTML.Engine.handle_body(body)

  @doc false
  def handle_text({:safe, buffer}, text), do: Phoenix.HTML.Engine.handle_text({:safe, buffer}, text)

  @doc false
  def handle_text("", text), do: Phoenix.HTML.Engine.handle_text("", text)

  @doc false
  def handle_expr("", marker, expr), do: Phoenix.HTML.Engine.handle_expr("", marker, expr)

  @doc false
  def handle_expr({:safe, buffer}, "=", expr) do
    # expr = Macro.prewalk(expr, &EEx.Engine.handle_assign/1)
    # quote do
    #   tmp1 = unquote(buffer)
    #   # tmp1  
    #   #   <> "<span id='#{unquote(uuid)}' drab-assigns='#{unquote(found_assigns)}' drab-expr='#{unquote(encoded_expr)}'>"
    #   #   <> String.Chars.to_string(unquote(expr)) 
    #   #   <> "</span>"
    #   tmp1 

    # IO.puts "********"
    # IO.inspect buffer
    # IO.puts "********"

    found_assigns = find_assigns(expr) |> Enum.join(",")
    found_assigns? = found_assigns != ""
    line   = line_from_expr(expr)
    expr   = expr(expr)
    encoded_expr = encode(expr)
    uuid = uuid()
    span = "<span id='#{uuid}' drab-assigns='#{found_assigns}' drab-expr='#{encoded_expr}'>"

    {:safe, quote do
      tmp1 = unquote(buffer)
      tmp1 = if unquote(found_assigns?) do
        [tmp1|unquote(span)]
      else
        tmp1
      end
      tmp1 = [tmp1|unquote(to_safe(expr, line))]
      if unquote(found_assigns?) do
        [tmp1|unquote("</span>")]
      else
        tmp1
      end
     end}
  end

  @doc false
  def handle_expr({:safe, buffer}, "", expr), do: Phoenix.HTML.Engine.handle_expr({:safe, buffer}, "", expr)

  defp line_from_expr({_, meta, _}) when is_list(meta), do: Keyword.get(meta, :line)
  defp line_from_expr(_), do: nil

  # We can do the work at compile time
  defp to_safe(literal, _line) when is_binary(literal) or is_atom(literal) or is_number(literal) do
    Phoenix.HTML.Safe.to_iodata(literal)
  end

  # We can do the work at runtime
  defp to_safe(literal, line) when is_list(literal) do
    quote line: line, do: Phoenix.HTML.Safe.to_iodata(unquote(literal))
  end

  # We need to check at runtime and we do so by
  # optimizing common cases.
  defp to_safe(expr, line) do
    # Keep stacktraces for protocol dispatch...
    fallback = quote line: line, do: Phoenix.HTML.Safe.to_iodata(other)

    # However ignore them for the generated clauses to avoid warnings
    quote @anno do
      case unquote(expr) do
        {:safe, data} -> data
        bin when is_binary(bin) -> Plug.HTML.html_escape(bin)
        other -> unquote(fallback)
      end
    end
  end

  defp expr(expr) do
    Macro.prewalk(expr, &handle_assign/1)
  end

  defp handle_assign({:@, meta, [{name, _, atom}]}) when is_atom(name) and is_atom(atom) do
    quote line: meta[:line] || 0 do
      Phoenix.HTML.Engine.fetch_assign(var!(assigns), unquote(name))
    end
  end
  defp handle_assign(arg), do: arg

  defp find_assigns(ast) do
    {_, result} = Macro.prewalk ast, [], fn node, acc ->
      case node do
        {:@, _, [{name, _, atom}]} when is_atom(name) and is_atom(atom) -> {node, [name | acc]} 
        _ -> {node, acc}
      end
    end
    result |> Enum.uniq 
  end


  # @doc false
  # def fetch_assign(assigns, key) do
  #   case Access.fetch(assigns, key) do
  #     {:ok, val} ->
  #       val
  #     :error ->
  #       raise ArgumentError, message: """
  #       assign @#{key} not available in eex template.
  #       Please make sure all proper assigns have been set. If this
  #       is a child template, ensure assigns are given explicitly by
  #       the parent template as they are not automatically forwarded.
  #       Available assigns: #{inspect Enum.map(assigns, &elem(&1, 0))}
  #       """
  #   end
  # end




  # def handle_expr(buffer, "=", expr) do
  #   found_assigns = find_assigns(expr) |> Enum.join(",")
  #   expr = Macro.prewalk(expr, &EEx.Engine.handle_assign/1)
  #   encoded_expr = encode(expr)
  #   uuid = uuid()
  #   quote do
  #     tmp1 = unquote(buffer)
  #     # tmp1  
  #     #   <> "<span id='#{unquote(uuid)}' drab-assigns='#{unquote(found_assigns)}' drab-expr='#{unquote(encoded_expr)}'>"
  #     #   <> String.Chars.to_string(unquote(expr)) 
  #     #   <> "</span>"
  #     tmp1 
  #   end
  # end

  # def handle_expr(buffer, "", expr) do
  #   super(buffer, "", expr)
  # end

  # def handle_expr(buffer, "#", expr) do
  #   super(buffer, "", expr)
  # end




  # def init(_opts) do
  #   ""
  # end

  # def handle_expr(buffer, mark, expr) do
  #   IO.inspect expr
  #   expr = inject_drab_span(expr)
  #   IO.inspect expr
  #   expr = Macro.prewalk(expr, &EEx.Engine.handle_assign/1)
  #   IO.inspect expr
  #   {a, b, [e, pre_string]} = buffer
  #   # IO.inspect x
  #   # IO.inspect pre_string
  #   IO.puts ""
  #   super({a, b, [e, pre_string]}, mark, expr)
  # end

  # defp inject_drab_span(expr) do
  #   quote do 
  #     "<span>" <> unquote(expr)
  #   end
  #   # tag regex = ~r/<([^\/].*)>/mis
  #   # s = "</div1>\n<b>dwa</b><div2 dupa='bada'><i id=1>xx</i>"
  #   # l = String.split(s, ~r/</) |> Enum.reverse()
  #   # quote do
  #   #   "<drab_id>" <> unquote(expr)
  #   # end
  # end

  def find_unclosed_tag(list) do
    Enum.reduce(list, {[], []}, fn(x, {acc, closed_tags}) -> 
      s = String.trim_leading(x)
      closing_match = ~r/^\/(.*)[\s>]/
      opening_match = ~r/^[^\/](.*)[\s>]/
      # IO.inspect Regex.match?(closing_match, s)
      cond do
        Regex.match?(closing_match, s) ->
          # IO.puts "#{s} closing, tag: #{tag(s)}"
          {acc ++ ["#{x} (closing)"], closed_tags ++ [tag(s)]}
        Regex.match?(opening_match, s) ->
          # IO.puts "#{s} opening, tag: #{tag(s)}"
          IO.inspect closed_tags
          {acc ++ ["#{x} OPEN"], closed_tags -- [tag(s)]}
        true -> {acc, closed_tags}
      end
      # [x] ++ acc
    end)
  end

  defp tag(string) do
    [_, match] = Regex.run(~r/^\/*([\S>]*)[\s>]+/, string)
    String.replace(match, ">", "")
  end
end