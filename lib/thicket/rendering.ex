defmodule Thicket.Rendering do
  @moduledoc "Versioned rendering and sanitization for locally authored content."

  @version 1
  @allowed_tags ~w(a abbr article aside b blockquote br code dd del details div dl dt em figcaption figure h1 h2 h3 h4 h5 h6 hr i img kbd li mark ol p pre q s samp section small span strong sub summary sup table tbody td th thead tr ul var)
  @global_attrs ~w(aria-label aria-hidden class dir lang role style title)
  @tag_attrs %{
    "a" => ~w(href rel target),
    "img" => ~w(src alt width height),
    "details" => ~w(open),
    "td" => ~w(colspan rowspan),
    "th" => ~w(colspan rowspan scope)
  }
  @dangerous_css ~r/(?:expression\s*\(|javascript\s*:|vbscript\s*:|behavior\s*:|-moz-binding|@import|url\s*\(\s*['"]?\s*(?!https:|data:image\/))/iu

  def version, do: @version

  def render(source, :markdown) when is_binary(source) do
    case MDEx.to_html(source, extension: [strikethrough: true, table: true, tasklist: true], render: [unsafe_: true]) do
      {:ok, html} -> sanitize(html)
      {:error, reason} -> {:error, reason}
    end
  end

  def render(source, :html) when is_binary(source), do: sanitize(source)
  def render(_source, _format), do: {:error, :unsupported_source_format}

  def sanitize(html) when is_binary(html) do
    with {:ok, tree} <- Floki.parse_fragment(html) do
      sanitized = Enum.flat_map(tree, &sanitize_node/1)
      {:ok, Floki.raw_html(sanitized), @version}
    end
  end

  def render_comment(source) when is_binary(source) do
    with {:ok, html} <- MDEx.to_html(source),
         {:ok, tree} <- Floki.parse_fragment(html) do
      sanitized = Enum.flat_map(tree, &sanitize_comment_node/1)
      {:ok, Floki.raw_html(sanitized), @version}
    end
  end

  defp sanitize_node(text) when is_binary(text), do: [text]
  defp sanitize_node({tag, _attrs, children}) when tag not in @allowed_tags,
    do: Enum.flat_map(children, &sanitize_node/1)

  defp sanitize_node({tag, attrs, children}) do
    [{tag, sanitize_attrs(tag, attrs), Enum.flat_map(children, &sanitize_node/1)}]
  end

  defp sanitize_node(_), do: []

  defp sanitize_comment_node(text) when is_binary(text), do: [text]
  defp sanitize_comment_node({tag, _attrs, children}) when tag not in @allowed_tags,
    do: Enum.flat_map(children, &sanitize_comment_node/1)

  defp sanitize_comment_node({tag, attrs, children}) do
    attrs = Enum.reject(attrs, fn {name, _value} -> name in ["style", "class"] end)
    [{tag, sanitize_attrs(tag, attrs), Enum.flat_map(children, &sanitize_comment_node/1)}]
  end

  defp sanitize_comment_node(_), do: []

  defp sanitize_attrs(tag, attrs) do
    allowed = @global_attrs ++ Map.get(@tag_attrs, tag, [])

    attrs
    |> Enum.filter(fn {name, _value} -> name in allowed or String.starts_with?(name, "aria-") end)
    |> Enum.flat_map(fn
      {"style", value} -> if safe_style?(value), do: [{"style", value}], else: []
      {name, value} when name in ["href", "src"] -> if safe_url?(value), do: [{name, value}], else: []
      {"target", "_blank"} -> [{"target", "_blank"}]
      {"target", _} -> []
      {name, value} -> [{name, value}]
    end)
    |> add_link_safety(tag)
  end

  defp add_link_safety(attrs, "a") do
    attrs
    |> Keyword.delete("rel")
    |> List.keystore("rel", 0, {"rel", "nofollow noopener noreferrer"})
  end

  defp add_link_safety(attrs, _tag), do: attrs

  defp safe_style?(style), do: byte_size(style) <= 20_000 and not Regex.match?(@dangerous_css, style)

  defp safe_url?(url) do
    case URI.parse(String.trim(url)) do
      %URI{scheme: scheme} when scheme in ["https", "http", "mailto"] -> true
      %URI{scheme: nil, host: nil} -> not String.starts_with?(url, "//")
      _ -> false
    end
  end
end
