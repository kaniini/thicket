defmodule Thicket.Moderation do
  @moduledoc "Local safety and administrator policy. No moderation action federates from this context."

  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias Thicket.Identity.{Channel, User}
  alias Thicket.Moderation.{AuditEvent, Block, DomainRule, Report}
  alias Thicket.Repo

  def block(%Channel{id: id}, %Channel{id: id}), do: {:error, :cannot_block_self}

  def block(%Channel{} = blocker, %Channel{} = blocked) do
    Repo.insert(%Block{blocker_channel_id: blocker.id, blocked_channel_id: blocked.id},
      on_conflict: :nothing,
      conflict_target: [:blocker_channel_id, :blocked_channel_id]
    )
  end

  def unblock(%Channel{} = blocker, %Channel{} = blocked) do
    Repo.delete_all(from b in Block, where: b.blocker_channel_id == ^blocker.id and b.blocked_channel_id == ^blocked.id)
    :ok
  end

  def blocked?(%Channel{id: blocker_id}, %Channel{id: blocked_id}) do
    Repo.exists?(from b in Block, where: b.blocker_channel_id == ^blocker_id and b.blocked_channel_id == ^blocked_id)
  end

  def report(%Channel{} = reporter, attrs) do
    %Report{reporter_channel_id: reporter.id} |> Report.changeset(attrs) |> Repo.insert()
  end

  def list_open_reports(%User{admin: true}) do
    Report |> where([r], r.state == :open) |> order_by(asc: :inserted_at) |> preload(:reporter_channel) |> Repo.all()
  end

  def list_open_reports(%User{}), do: {:error, :unauthorized}

  def get_report!(%User{admin: true}, id), do: Repo.get!(Report, id)

  def resolve_report(%User{admin: true} = admin, %Report{} = report, state)
      when state in [:resolved, :dismissed] do
    now = DateTime.utc_now(:second)

    Multi.new()
    |> Multi.update(:report, Ecto.Changeset.change(report, state: state, resolved_by_id: admin.id, resolved_at: now))
    |> Multi.insert(:audit, %AuditEvent{actor_user_id: admin.id, action: "report.#{state}", subject_type: "report", subject_id: report.id})
    |> Repo.transaction()
  end

  def put_domain_rule(%User{admin: true} = admin, attrs) do
    Multi.new()
    |> Multi.insert(:rule, %DomainRule{created_by_id: admin.id} |> DomainRule.changeset(attrs))
    |> Multi.insert(:audit, fn %{rule: rule} ->
      Ecto.Changeset.change(%AuditEvent{}, %{actor_user_id: admin.id, action: "domain.suspend", subject_type: "domain_rule", subject_id: rule.id})
    end)
    |> Repo.transaction()
  end

  def put_domain_rule(%User{}, _attrs), do: {:error, :unauthorized}

  def list_domain_rules(%User{admin: true}), do: Repo.all(from r in DomainRule, order_by: [asc: r.domain])
  def list_domain_rules(%User{}), do: {:error, :unauthorized}
end
