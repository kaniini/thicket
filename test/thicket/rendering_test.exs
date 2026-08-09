defmodule Thicket.RenderingTest do
  use ExUnit.Case, async: true
  alias Thicket.Rendering

  test "renders Markdown and sanitizes active content" do
    assert {:ok, html, 1} = Rendering.render("# Hello\n\n<script>alert(1)</script><a href=\"javascript:alert(1)\">bad</a>", :markdown)
    assert html =~ "<h1>Hello</h1>"
    refute html =~ "<script"
    refute html =~ "javascript:"
  end

  test "preserves safe inline presentation and details while rejecting executable CSS" do
    source = "<details open><summary>look</summary><div style=\"display:flex;color:red\">ok</div><p style=\"background:url(javascript:x)\">bad</p></details>"
    assert {:ok, html, 1} = Rendering.render(source, :html)
    assert html =~ "<details open=\"open\">"
    assert html =~ "display:flex;color:red"
    refute html =~ "background:url"
  end

  test "comment Markdown does not admit custom HTML or style" do
    assert {:ok, html, 1} = Rendering.render_comment("**safe** <span style=\"position:fixed\">no</span>")
    assert html =~ "<strong>safe</strong>"
    refute html =~ "position:fixed"
  end
end
