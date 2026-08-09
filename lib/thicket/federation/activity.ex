defmodule Thicket.Federation.Activity do
  @enforce_keys [:id, :type, :actor]
  defstruct [
    :id,
    :type,
    :actor,
    :object,
    :published,
    recipients: %Thicket.Federation.Recipients{},
    extensions: %{}
  ]
end
