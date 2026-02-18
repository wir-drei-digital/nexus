defmodule Nexus.Content.TiptapRendererTest do
  use ExUnit.Case, async: true

  alias Nexus.Content.TiptapRenderer

  describe "render/1" do
    test "renders a paragraph" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Hello world"}]}
        ]
      }

      assert TiptapRenderer.render(doc) == "<p>Hello world</p>"
    end

    test "renders headings" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "heading",
            "attrs" => %{"level" => 1},
            "content" => [%{"type" => "text", "text" => "Title"}]
          },
          %{
            "type" => "heading",
            "attrs" => %{"level" => 3},
            "content" => [%{"type" => "text", "text" => "Subtitle"}]
          }
        ]
      }

      html = TiptapRenderer.render(doc)
      assert html =~ "<h1>Title</h1>"
      assert html =~ "<h3>Subtitle</h3>"
    end

    test "renders bold and italic marks" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{
                "type" => "text",
                "text" => "bold",
                "marks" => [%{"type" => "bold"}]
              },
              %{"type" => "text", "text" => " and "},
              %{
                "type" => "text",
                "text" => "italic",
                "marks" => [%{"type" => "italic"}]
              }
            ]
          }
        ]
      }

      assert TiptapRenderer.render(doc) == "<p><strong>bold</strong> and <em>italic</em></p>"
    end

    test "renders nested marks" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{
                "type" => "text",
                "text" => "bold italic",
                "marks" => [%{"type" => "bold"}, %{"type" => "italic"}]
              }
            ]
          }
        ]
      }

      assert TiptapRenderer.render(doc) ==
               "<p><em><strong>bold italic</strong></em></p>"
    end

    test "renders underline, strike, and code marks" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{"type" => "text", "text" => "under", "marks" => [%{"type" => "underline"}]},
              %{"type" => "text", "text" => " "},
              %{"type" => "text", "text" => "struck", "marks" => [%{"type" => "strike"}]},
              %{"type" => "text", "text" => " "},
              %{"type" => "text", "text" => "mono", "marks" => [%{"type" => "code"}]}
            ]
          }
        ]
      }

      html = TiptapRenderer.render(doc)
      assert html =~ "<u>under</u>"
      assert html =~ "<s>struck</s>"
      assert html =~ "<code>mono</code>"
    end

    test "renders link mark" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{
                "type" => "text",
                "text" => "click",
                "marks" => [
                  %{
                    "type" => "link",
                    "attrs" => %{"href" => "https://example.com", "target" => "_blank"}
                  }
                ]
              }
            ]
          }
        ]
      }

      html = TiptapRenderer.render(doc)
      assert html =~ ~s(href="https://example.com")
      assert html =~ ~s(target="_blank")
      assert html =~ ~s(rel="noopener noreferrer")
      assert html =~ ">click</a>"
    end

    test "renders bullet list" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "bulletList",
            "content" => [
              %{
                "type" => "listItem",
                "content" => [
                  %{
                    "type" => "paragraph",
                    "content" => [%{"type" => "text", "text" => "One"}]
                  }
                ]
              },
              %{
                "type" => "listItem",
                "content" => [
                  %{
                    "type" => "paragraph",
                    "content" => [%{"type" => "text", "text" => "Two"}]
                  }
                ]
              }
            ]
          }
        ]
      }

      html = TiptapRenderer.render(doc)
      assert html =~ "<ul>"
      assert html =~ "<li>"
      assert html =~ "One"
      assert html =~ "Two"
    end

    test "renders ordered list" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "orderedList",
            "content" => [
              %{
                "type" => "listItem",
                "content" => [
                  %{
                    "type" => "paragraph",
                    "content" => [%{"type" => "text", "text" => "First"}]
                  }
                ]
              }
            ]
          }
        ]
      }

      assert TiptapRenderer.render(doc) =~ "<ol>"
    end

    test "renders blockquote" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "blockquote",
            "content" => [
              %{
                "type" => "paragraph",
                "content" => [%{"type" => "text", "text" => "Be yourself"}]
              }
            ]
          }
        ]
      }

      html = TiptapRenderer.render(doc)
      assert html =~ "<blockquote>"
      assert html =~ "Be yourself"
    end

    test "renders code block with language" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "codeBlock",
            "attrs" => %{"language" => "elixir"},
            "content" => [%{"type" => "text", "text" => "x = 1"}]
          }
        ]
      }

      html = TiptapRenderer.render(doc)
      assert html =~ "<pre><code"
      assert html =~ "language-elixir"
      assert html =~ "x = 1"
    end

    test "renders code block without language" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "codeBlock",
            "attrs" => %{},
            "content" => [%{"type" => "text", "text" => "plain code"}]
          }
        ]
      }

      html = TiptapRenderer.render(doc)
      assert html =~ "<pre><code>plain code</code></pre>"
    end

    test "renders image" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "image",
            "attrs" => %{"src" => "https://example.com/img.jpg", "alt" => "Photo"}
          }
        ]
      }

      html = TiptapRenderer.render(doc)
      assert html =~ ~s(<img src="https://example.com/img.jpg" alt="Photo">)
    end

    test "renders horizontal rule" do
      doc = %{
        "type" => "doc",
        "content" => [%{"type" => "horizontalRule"}]
      }

      assert TiptapRenderer.render(doc) == "<hr>"
    end

    test "renders hard break in inline content" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{"type" => "text", "text" => "line one"},
              %{"type" => "hardBreak"},
              %{"type" => "text", "text" => "line two"}
            ]
          }
        ]
      }

      assert TiptapRenderer.render(doc) == "<p>line one<br>line two</p>"
    end

    test "escapes HTML in text content" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{"type" => "text", "text" => "<script>alert('xss')</script>"}
            ]
          }
        ]
      }

      html = TiptapRenderer.render(doc)
      refute html =~ "<script>"
      assert html =~ "&lt;script&gt;"
    end

    test "returns empty string for nil" do
      assert TiptapRenderer.render(nil) == ""
    end

    test "returns empty string for empty doc" do
      assert TiptapRenderer.render(%{"type" => "doc", "content" => []}) == ""
    end

    test "returns empty string for doc without content key" do
      assert TiptapRenderer.render(%{"type" => "doc"}) == ""
    end

    test "renders empty paragraph" do
      doc = %{
        "type" => "doc",
        "content" => [%{"type" => "paragraph"}]
      }

      assert TiptapRenderer.render(doc) == "<p></p>"
    end

    test "strips javascript: links but keeps text" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{
                "type" => "text",
                "text" => "click me",
                "marks" => [
                  %{"type" => "link", "attrs" => %{"href" => "javascript:alert(1)"}}
                ]
              }
            ]
          }
        ]
      }

      html = TiptapRenderer.render(doc)
      refute html =~ "javascript:"
      assert html =~ "click me"
      refute html =~ "<a"
    end

    test "strips data: image src" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "image",
            "attrs" => %{"src" => "data:text/html,<script>alert(1)</script>", "alt" => "bad"}
          }
        ]
      }

      html = TiptapRenderer.render(doc)
      refute html =~ "data:"
      refute html =~ "<img"
    end

    test "allows relative URLs in links" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{
                "type" => "text",
                "text" => "page",
                "marks" => [
                  %{"type" => "link", "attrs" => %{"href" => "/about"}}
                ]
              }
            ]
          }
        ]
      }

      html = TiptapRenderer.render(doc)
      assert html =~ ~s(href="/about")
    end

    test "ignores unknown node types" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{"type" => "unknownBlock"},
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "ok"}]}
        ]
      }

      assert TiptapRenderer.render(doc) =~ "<p>ok</p>"
    end

    test "ignores unknown mark types" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{
                "type" => "text",
                "text" => "hello",
                "marks" => [%{"type" => "superscript"}]
              }
            ]
          }
        ]
      }

      assert TiptapRenderer.render(doc) == "<p>hello</p>"
    end
  end
end
