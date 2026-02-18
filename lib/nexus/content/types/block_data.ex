defmodule Nexus.Content.Types.BlockData do
  use Ash.Type.NewType,
    subtype_of: :union,
    constraints: [
      types: [
        text: [
          type: :map,
          constraints: [
            fields: [
              content: [type: :string, allow_nil?: false]
            ]
          ],
          tag: :type,
          tag_value: :text
        ],
        heading: [
          type: :map,
          constraints: [
            fields: [
              content: [type: :string, allow_nil?: false],
              level: [type: :integer, allow_nil?: false, constraints: [min: 1, max: 6]]
            ]
          ],
          tag: :type,
          tag_value: :heading
        ],
        image: [
          type: :map,
          constraints: [
            fields: [
              url: [type: :string, allow_nil?: false],
              alt: [type: :string],
              caption: [type: :string]
            ]
          ],
          tag: :type,
          tag_value: :image
        ],
        code: [
          type: :map,
          constraints: [
            fields: [
              content: [type: :string, allow_nil?: false],
              language: [type: :string]
            ]
          ],
          tag: :type,
          tag_value: :code
        ],
        quote: [
          type: :map,
          constraints: [
            fields: [
              content: [type: :string, allow_nil?: false],
              attribution: [type: :string]
            ]
          ],
          tag: :type,
          tag_value: :quote
        ],
        list: [
          type: :map,
          constraints: [
            fields: [
              style: [
                type: :atom,
                allow_nil?: false,
                constraints: [one_of: [:ordered, :unordered]]
              ],
              items: [type: {:array, :string}, allow_nil?: false]
            ]
          ],
          tag: :type,
          tag_value: :list
        ],
        divider: [
          type: :map,
          constraints: [fields: []],
          tag: :type,
          tag_value: :divider
        ]
      ]
    ]
end
