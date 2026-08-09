defmodule Thicket.Federation.Collection do
  @enforce_keys [:id, :type]
  defstruct [:id, :type, :total_items, :first, :next, :prev, ordered_items: [], items: []]
end
