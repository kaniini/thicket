defmodule Thicket.Federation.PublicKey do
  @enforce_keys [:id, :owner, :public_key_pem]
  defstruct [:id, :owner, :public_key_pem]
end
