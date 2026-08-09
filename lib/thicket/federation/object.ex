defmodule Thicket.Federation.Object do
  @enforce_keys [:id, :type]
  defstruct [
    :id,
    :type,
    :attributed_to,
    :name,
    :summary,
    :content,
    :media_type,
    :source,
    :in_reply_to,
    :published,
    :updated,
    recipients: %Thicket.Federation.Recipients{},
    attachments: [],
    mentions: [],
    extensions: %{}
  ]
end
