defmodule Thicket.Federation.Error do
  @moduledoc "A structured error returned for malformed remote documents."

  @enforce_keys [:code, :path, :message]
  defstruct [:code, :path, :message]

  @type t :: %__MODULE__{
          code: atom(),
          path: [String.t() | non_neg_integer()],
          message: String.t()
        }
end
