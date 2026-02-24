defmodule Nexus.AI.ProseMirrorTest do
  use ExUnit.Case, async: true

  alias Nexus.AI.ProseMirror

  describe "to_markdown/1" do
    test "returns empty string for nil" do
      assert ProseMirror.to_markdown(nil) == ""
    end

    test "returns empty string for empty doc" do
      assert ProseMirror.to_markdown(%{"type" => "doc"}) == ""
    end

    test "returns empty string for doc with empty content" do
      assert ProseMirror.to_markdown(%{"type" => "doc", "content" => []}) == ""
    end

    test "returns empty string for unknown input" do
      assert ProseMirror.to_markdown(%{"something" => "else"}) == ""
      assert ProseMirror.to_markdown("string") == ""
      assert ProseMirror.to_markdown(42) == ""
    end

    test "converts a simple paragraph" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [%{"type" => "text", "text" => "Hello world"}]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "Hello world"
    end

    test "converts multiple paragraphs" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [%{"type" => "text", "text" => "First paragraph"}]
          },
          %{
            "type" => "paragraph",
            "content" => [%{"type" => "text", "text" => "Second paragraph"}]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "First paragraph\n\nSecond paragraph"
    end

    test "converts empty paragraph" do
      doc = %{
        "type" => "doc",
        "content" => [%{"type" => "paragraph"}]
      }

      assert ProseMirror.to_markdown(doc) == ""
    end

    test "converts headings with levels" do
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
            "attrs" => %{"level" => 2},
            "content" => [%{"type" => "text", "text" => "Subtitle"}]
          },
          %{
            "type" => "heading",
            "attrs" => %{"level" => 3},
            "content" => [%{"type" => "text", "text" => "Section"}]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "# Title\n\n## Subtitle\n\n### Section"
    end

    test "converts bold text" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{"type" => "text", "text" => "This is "},
              %{"type" => "text", "text" => "bold", "marks" => [%{"type" => "bold"}]},
              %{"type" => "text", "text" => " text"}
            ]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "This is **bold** text"
    end

    test "converts italic text" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{"type" => "text", "text" => "This is "},
              %{"type" => "text", "text" => "italic", "marks" => [%{"type" => "italic"}]},
              %{"type" => "text", "text" => " text"}
            ]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "This is *italic* text"
    end

    test "converts strikethrough text" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{
                "type" => "text",
                "text" => "deleted",
                "marks" => [%{"type" => "strike"}]
              }
            ]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "~~deleted~~"
    end

    test "converts inline code" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{"type" => "text", "text" => "Use "},
              %{"type" => "text", "text" => "mix test", "marks" => [%{"type" => "code"}]},
              %{"type" => "text", "text" => " to run tests"}
            ]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "Use `mix test` to run tests"
    end

    test "converts link" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{"type" => "text", "text" => "Visit "},
              %{
                "type" => "text",
                "text" => "Elixir",
                "marks" => [
                  %{"type" => "link", "attrs" => %{"href" => "https://elixir-lang.org"}}
                ]
              }
            ]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "Visit [Elixir](https://elixir-lang.org)"
    end

    test "converts nested marks (bold + italic)" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{
                "type" => "text",
                "text" => "emphasis",
                "marks" => [%{"type" => "bold"}, %{"type" => "italic"}]
              }
            ]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "***emphasis***"
    end

    test "converts bullet list" do
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
                    "content" => [%{"type" => "text", "text" => "First item"}]
                  }
                ]
              },
              %{
                "type" => "listItem",
                "content" => [
                  %{
                    "type" => "paragraph",
                    "content" => [%{"type" => "text", "text" => "Second item"}]
                  }
                ]
              }
            ]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "- First item\n- Second item"
    end

    test "converts ordered list" do
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
              },
              %{
                "type" => "listItem",
                "content" => [
                  %{
                    "type" => "paragraph",
                    "content" => [%{"type" => "text", "text" => "Second"}]
                  }
                ]
              }
            ]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "1. First\n2. Second"
    end

    test "converts code block without language" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "codeBlock",
            "content" => [%{"type" => "text", "text" => "defmodule Foo do\nend"}]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "```\ndefmodule Foo do\nend\n```"
    end

    test "converts code block with language" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "codeBlock",
            "attrs" => %{"language" => "elixir"},
            "content" => [%{"type" => "text", "text" => "IO.puts(\"hello\")"}]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "```elixir\nIO.puts(\"hello\")\n```"
    end

    test "converts empty code block" do
      doc = %{
        "type" => "doc",
        "content" => [%{"type" => "codeBlock"}]
      }

      assert ProseMirror.to_markdown(doc) == "```\n\n```"
    end

    test "converts blockquote" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "blockquote",
            "content" => [
              %{
                "type" => "paragraph",
                "content" => [%{"type" => "text", "text" => "A wise quote"}]
              }
            ]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "> A wise quote"
    end

    test "converts blockquote with multiple paragraphs" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "blockquote",
            "content" => [
              %{
                "type" => "paragraph",
                "content" => [%{"type" => "text", "text" => "First line"}]
              },
              %{
                "type" => "paragraph",
                "content" => [%{"type" => "text", "text" => "Second line"}]
              }
            ]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "> First line\n>\n> Second line"
    end

    test "converts horizontal rule" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [%{"type" => "text", "text" => "Above"}]
          },
          %{"type" => "horizontalRule"},
          %{
            "type" => "paragraph",
            "content" => [%{"type" => "text", "text" => "Below"}]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "Above\n\n---\n\nBelow"
    end

    test "converts image with alt text" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "image",
            "attrs" => %{"src" => "https://example.com/photo.jpg", "alt" => "A photo"}
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "![A photo](https://example.com/photo.jpg)"
    end

    test "converts image without alt text" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "image",
            "attrs" => %{"src" => "https://example.com/photo.jpg"}
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "![](https://example.com/photo.jpg)"
    end

    test "converts hard break" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{"type" => "text", "text" => "Line one"},
              %{"type" => "hardBreak"},
              %{"type" => "text", "text" => "Line two"}
            ]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "Line one\nLine two"
    end

    test "ignores unknown node types" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{"type" => "unknownWidget"},
          %{
            "type" => "paragraph",
            "content" => [%{"type" => "text", "text" => "Normal text"}]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "Normal text"
    end

    test "converts bold link" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{
                "type" => "text",
                "text" => "click here",
                "marks" => [
                  %{"type" => "bold"},
                  %{"type" => "link", "attrs" => %{"href" => "https://example.com"}}
                ]
              }
            ]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "[**click here**](https://example.com)"
    end

    test "roundtrip: markdown -> prosemirror -> markdown preserves content" do
      original = "Hello **world** and *italic* text"

      {:ok, prosemirror} = ProseMirror.from_markdown(original)
      result = ProseMirror.to_markdown(prosemirror)

      assert result == original
    end
  end
end
