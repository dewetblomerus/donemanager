defmodule DoneManager.Households do
  @moduledoc """
  Households, memberships, and invitations.

  Read/write functions take a `%Scope{}` and only ever touch the scope's
  household, so cross-household access is structurally impossible. Invitation
  acceptance is keyed on the signed-in user's email, not a household scope,
  because the invitee acts before they belong to the household.
  """

  import Ecto.Query, warn: false

  alias DoneManager.Accounts.Scope
  alias DoneManager.Accounts.User
  alias DoneManager.Households.Household
  alias DoneManager.Households.HouseholdInvitation
  alias DoneManager.Households.HouseholdMembership
  alias DoneManager.Repo

  ## Households

  @doc "Households the scope's user belongs to, oldest membership first."
  def list_households(%Scope{user: %User{id: user_id}}) do
    from(h in Household,
      join: m in HouseholdMembership,
      on: m.household_id == h.id,
      where: m.user_id == ^user_id,
      order_by: [asc: m.inserted_at]
    )
    |> Repo.all()
  end

  @doc "Fetches a household the scope's user belongs to, or raises (default-deny)."
  def get_household!(%Scope{user: %User{id: user_id}}, id) do
    from(h in Household,
      join: m in HouseholdMembership,
      on: m.household_id == h.id,
      where: m.user_id == ^user_id and h.id == ^id
    )
    |> Repo.one!()
  end

  @doc "The household to make current for a freshly-loaded scope, or nil."
  def default_household(%Scope{} = scope), do: List.first(list_households(scope))

  @doc "Creates a household and makes the scope's user its owner."
  def create_household(%Scope{user: %User{} = user}, attrs) do
    Repo.transaction(fn ->
      household =
        %Household{}
        |> Household.changeset(attrs)
        |> Repo.insert()
        |> unwrap()

      %HouseholdMembership{}
      |> HouseholdMembership.changeset(%{
        household_id: household.id,
        user_id: user.id,
        role: "owner"
      })
      |> Repo.insert()
      |> unwrap()

      household
    end)
  end

  def change_household(%Household{} = household \\ %Household{}, attrs \\ %{}),
    do: Household.changeset(household, attrs)

  ## Memberships

  @doc "Members of the scope's current household, with their user preloaded."
  def list_memberships(%Scope{household: %Household{id: household_id}}) do
    from(m in HouseholdMembership,
      where: m.household_id == ^household_id,
      order_by: [asc: m.inserted_at],
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc "Whether the scope's user owns the scope's current household."
  def owner?(%Scope{user: %User{id: user_id}, household: %Household{id: household_id}}) do
    Repo.exists?(
      from m in HouseholdMembership,
        where: m.user_id == ^user_id and m.household_id == ^household_id and m.role == "owner"
    )
  end

  def owner?(_scope), do: false

  ## Invitations

  @doc "Pending invitations for the scope's current household."
  def list_invitations(%Scope{household: %Household{id: household_id}}) do
    from(i in HouseholdInvitation,
      where: i.household_id == ^household_id and i.status == "pending",
      order_by: [asc: i.inserted_at]
    )
    |> Repo.all()
  end

  @doc "Pending invitations addressed to the given user's email, across households."
  def list_pending_invitations_for_user(%User{email: email}) do
    normalized = String.downcase(email)

    from(i in HouseholdInvitation,
      where: i.invitee_email == ^normalized and i.status == "pending",
      order_by: [asc: i.inserted_at],
      preload: [:household]
    )
    |> Repo.all()
  end

  @doc "Owner-only: invites an email to the scope's current household."
  def invite_by_email(%Scope{user: %User{} = user} = scope, attrs) do
    if owner?(scope) do
      %HouseholdInvitation{}
      |> HouseholdInvitation.changeset(
        Map.merge(attrs, %{
          "household_id" => scope.household.id,
          "inviter_id" => user.id,
          "status" => "pending"
        })
      )
      |> Repo.insert()
    else
      {:error, :unauthorized}
    end
  end

  def change_invitation(
        %HouseholdInvitation{} = invitation \\ %HouseholdInvitation{},
        attrs \\ %{}
      ),
      do: HouseholdInvitation.changeset(invitation, attrs)

  @doc """
  Accepts a pending invitation addressed to the user, creating a membership.
  Authorized by the invite's `invitee_email` matching the user's email.
  """
  def accept_invitation(%User{} = user, invitation_id) do
    Repo.transaction(fn ->
      invitation = Repo.get(HouseholdInvitation, invitation_id)

      with %HouseholdInvitation{status: "pending"} <- invitation,
           true <- invitation.invitee_email == String.downcase(user.email),
           false <- expired?(invitation) do
        %HouseholdMembership{}
        |> HouseholdMembership.changeset(%{
          household_id: invitation.household_id,
          user_id: user.id,
          role: "member"
        })
        |> Repo.insert()
        |> unwrap()

        invitation
        |> HouseholdInvitation.changeset(%{status: "accepted"})
        |> Repo.update()
        |> unwrap()
      else
        _ -> Repo.rollback(:invalid_invitation)
      end
    end)
  end

  defp expired?(%HouseholdInvitation{expires_at: nil}), do: false

  defp expired?(%HouseholdInvitation{expires_at: at}),
    do: DateTime.compare(at, DateTime.utc_now()) == :lt

  defp unwrap({:ok, record}), do: record
  defp unwrap({:error, changeset}), do: Repo.rollback(changeset)
end
