defmodule Thicket.Federation.Actor do
  @enforce_keys [:id, :type]
  defstruct [
    :id,
    :type,
    :preferred_username,
    :name,
    :summary,
    :inbox,
    :outbox,
    :followers,
    :following,
    :shared_inbox,
    :public_key,
    :icon,
    :image,
    extensions: %{}
  ]
end
