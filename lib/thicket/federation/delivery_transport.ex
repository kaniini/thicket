defmodule Thicket.Federation.DeliveryTransport do
  @moduledoc false
  @callback post(String.t(), [{String.t(), String.t()}], binary()) ::
              {:ok, non_neg_integer()} | {:error, term()}
end
