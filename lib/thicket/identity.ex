defmodule Thicket.Identity do
  @moduledoc """
  The Identity context.
  """

  import Ecto.Query, warn: false
  alias Thicket.Repo

  alias Thicket.Identity.{Channel, ChannelMembership, Invitation, User, UserToken, UserNotifier}

  ## Invitations and channels

  def list_invitations do
    Invitation |> order_by(desc: :inserted_at) |> preload(:issuer) |> Repo.all()
  end

  def create_invitation(issuer, attrs \\ %{})

  def create_invitation(%User{admin: true} = issuer, attrs) do
    secret = :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)

    changeset =
      %Invitation{issuer_id: issuer.id, secret_digest: invitation_digest(secret)}
      |> Invitation.create_changeset(attrs)

    case Repo.insert(changeset) do
      {:ok, invitation} -> {:ok, invitation, secret}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def create_invitation(%User{}, _attrs), do: {:error, :unauthorized}

  @doc false
  def create_operator_invitation(attrs \\ %{}) do
    secret = :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
    changeset = %Invitation{secret_digest: invitation_digest(secret)} |> Invitation.create_changeset(attrs)

    case Repo.insert(changeset) do
      {:ok, invitation} -> {:ok, invitation, secret}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc false
  def promote_admin(email) when is_binary(email) do
    case get_user_by_email(email) do
      nil -> {:error, :not_found}
      user -> user |> Ecto.Changeset.change(admin: true) |> Repo.update()
    end
  end

  def revoke_invitation(%User{admin: true}, %Invitation{} = invitation) do
    invitation |> Ecto.Changeset.change(revoked_at: DateTime.utc_now(:second)) |> Repo.update()
  end

  def revoke_invitation(%User{}, %Invitation{}), do: {:error, :unauthorized}

  def list_channels(%User{id: user_id}) do
    Channel
    |> join(:inner, [c], m in ChannelMembership, on: m.channel_id == c.id)
    |> where([_c, m], m.user_id == ^user_id)
    |> order_by([c], asc: c.handle)
    |> Repo.all()
  end

  def scope_for_user(user, channel_id \\ nil)

  def scope_for_user(nil, _channel_id), do: nil

  def scope_for_user(%User{} = user, channel_id) do
    channels = list_channels(user)
    channel = Enum.find(channels, &(&1.id == channel_id)) || List.first(channels)
    Thicket.Identity.Scope.for_user(user, channel)
  end

  def get_channel_by_handle(handle) when is_binary(handle) do
    Repo.get_by(Channel, handle: String.downcase(handle))
  end

  def get_channel_for_user!(%User{id: user_id}, channel_id) do
    Channel
    |> join(:inner, [c], m in ChannelMembership, on: m.channel_id == c.id)
    |> where([c, m], c.id == ^channel_id and m.user_id == ^user_id)
    |> Repo.one!()
  end

  def create_channel(%User{} = user, attrs) do
    Repo.transact(fn ->
      with {:ok, channel} <- Repo.insert(Channel.changeset(%Channel{}, attrs)),
           {:ok, _membership} <-
             %ChannelMembership{user_id: user.id, channel_id: channel.id}
             |> ChannelMembership.changeset(%{role: :owner})
             |> Repo.insert() do
        {:ok, channel}
      end
    end)
  end

  def change_channel(%Channel{} = channel, attrs \\ %{}), do: Channel.changeset(channel, attrs)

  def update_channel(%User{} = user, %Channel{} = channel, attrs) do
    _authorized = get_channel_for_user!(user, channel.id)
    channel |> Channel.changeset(attrs) |> Repo.update()
  end

  @doc "Registers a user and their first channel by atomically redeeming an invitation."
  def register_invited_user(attrs) do
    invite_code = Map.get(attrs, "invite_code") || Map.get(attrs, :invite_code)
    channel_attrs = Map.take(attrs, ["handle", "display_name", :handle, :display_name])

    Repo.transaction(fn ->
      invitation =
        Invitation
        |> where([i], i.secret_digest == ^invitation_digest(invite_code || ""))
        |> lock("FOR UPDATE")
        |> Repo.one()

      if invitation && Invitation.available?(invitation) do
        with {:ok, user} <- %User{} |> User.registration_changeset(attrs) |> Repo.insert(),
             {:ok, channel} <- %Channel{} |> Channel.changeset(channel_attrs) |> Repo.insert(),
             {:ok, _membership} <-
               %ChannelMembership{user_id: user.id, channel_id: channel.id}
               |> ChannelMembership.changeset(%{role: :owner})
               |> Repo.insert(),
             {:ok, _invitation} <-
               invitation
               |> Ecto.Changeset.change(redemption_count: invitation.redemption_count + 1)
               |> Repo.update() do
          user
        else
          {:error, changeset} -> Repo.rollback(changeset)
        end
      else
        changeset =
          %User{}
          |> User.registration_changeset(attrs, validate_unique: false)
          |> Ecto.Changeset.add_error(:invite_code, "is invalid, expired, revoked, or fully redeemed")

        Repo.rollback(changeset)
      end
    end)
  end

  defp invitation_digest(secret), do: :crypto.hash(:sha256, secret)

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Thicket.Identity.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Thicket.Identity.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
