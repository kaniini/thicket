defmodule ThicketWeb.PostLive.Form do
  use ThicketWeb, :live_view
  alias Thicket.{Rendering, Social}
  alias Thicket.Social.Post

  @impl true
  def mount(params, _session, socket) do
    post =
      case params do
        %{"id" => id} -> Social.get_post!(id)
        _ -> %Post{source_format: :markdown, state: :draft}
      end

    if post.channel_id && post.channel_id != socket.assigns.current_scope.channel.id do
      {:ok,
       socket |> put_flash(:error, "You cannot edit that post") |> push_navigate(to: ~p"/home")}
    else
      {:ok,
       socket
       |> assign(:post, post)
       |> assign(:preview, post.rendered_html)
       |> assign(:form, to_form(Social.change_post(post)))
       |> allow_upload(:images,
         accept: ~w(.avif .gif .jpeg .jpg .png .webp),
         max_entries: 8,
         max_file_size: 20_000_000
       )}
    end
  end

  @impl true
  def handle_event("validate", %{"post" => params}, socket) do
    changeset = Social.change_post(socket.assigns.post, params)
    preview = render_preview(params)

    {:noreply,
     socket
     |> assign(:form, to_form(%{changeset | action: :validate}))
     |> assign(:preview, preview)}
  end

  def handle_event("save", %{"post" => params, "intent" => intent}, socket) do
    params = Map.put(params, "state", if(intent == "publish", do: "published", else: "draft"))
    descriptions = Map.get(params, "attachment_descriptions", "")

    if valid_upload_descriptions?(socket, descriptions) do
      channel = socket.assigns.current_scope.channel

      result =
        if socket.assigns.post.id,
          do: Social.update_post(channel, socket.assigns.post, params),
          else: Social.create_post(channel, params)

      case result do
        {:ok, post} ->
          save_uploads(socket, post, descriptions)

          destination =
            if post.state == :published,
              do: ~p"/posts/#{post.id}",
              else: ~p"/posts/#{post.id}/edit"

          {:noreply,
           socket
           |> put_flash(:info, if(post.state == :published, do: "Published", else: "Draft saved"))
           |> push_navigate(to: destination)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not save post")}
      end
    else
      {:noreply,
       put_flash(socket, :error, "Every uploaded image needs a description on its own line")}
    end
  end

  defp render_preview(%{"source" => source, "source_format" => format}) do
    case Rendering.render(source, String.to_existing_atom(format)) do
      {:ok, html, _} -> html
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  defp render_preview(_), do: nil

  defp valid_upload_descriptions?(socket, source) do
    description_count = source |> String.split("\n", trim: true) |> length()
    description_count >= length(socket.assigns.uploads.images.entries)
  end

  defp save_uploads(socket, post, descriptions_source) do
    descriptions = String.split(descriptions_source, "\n", trim: true)

    socket
    |> consume_uploaded_entries(:images, fn %{path: path}, entry ->
      position =
        Enum.find_index(socket.assigns.uploads.images.entries, &(&1.ref == entry.ref)) || 0

      description = Enum.at(descriptions, position)

      if is_nil(description) or description == "" do
        {:postpone, :missing_description}
      else
        with {:ok, key} <- Thicket.Storage.put(path, entry.client_type),
             {:ok, attachment} <-
               Social.add_attachment(socket.assigns.current_scope.channel, post, %{
                 storage_key: key,
                 media_type: entry.client_type,
                 byte_size: entry.client_size,
                 description: description,
                 position: position
               }) do
          {:ok, attachment}
        end
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="grid gap-8 lg:grid-cols-2">
        <section>
          <p class="text-sm font-semibold uppercase tracking-widest text-emerald-700">
            Compose as @{@current_scope.channel.handle}
          </p>
          <h1 class="mb-6 text-4xl font-black">{if @post.id, do: "Edit post", else: "New post"}</h1>
          <.form for={@form} id="post-form" phx-change="validate" phx-submit="save" class="space-y-5">
            <.input field={@form[:title]} type="text" label="Title (optional)" />
            <.input field={@form[:content_warning]} type="text" label="Content warning (optional)" />
            <.input
              field={@form[:source_format]}
              type="select"
              label="Writing mode"
              options={[{"Markdown", :markdown}, {"HTML + inline CSS", :html}]}
            />
            <.input field={@form[:source]} type="textarea" label="Post" rows="18" required />
            <.input field={@form[:comments_locked]} type="checkbox" label="Lock comments" />
            <div>
              <label class="mb-1 block text-sm font-semibold">Images</label>
              <.live_file_input
                upload={@uploads.images}
                class="block w-full rounded-xl border border-slate-300 bg-white p-3"
              />
              <p class="mt-1 text-xs text-slate-500">Up to 8 images, 20 MB each.</p>
            </div>
            <.input
              field={@form[:attachment_descriptions]}
              type="textarea"
              label="Image descriptions (one line per image, in order)"
            />
            <div class="flex gap-3">
              <.button name="intent" value="draft" class="btn">Save draft</.button><.button
                name="intent"
                value="publish"
                class="btn btn-primary"
              >Publish</.button>
            </div>
          </.form>
        </section>
        <aside>
          <h2 class="mb-4 text-sm font-semibold uppercase tracking-widest text-slate-500">
            Exact sanitized preview
          </h2>
          <div class="rounded-3xl border border-slate-200 bg-white p-6">
            <.rendered_post :if={@preview} html={@preview} post_id={@post.id || "preview"} />
            <p :if={!@preview} class="text-slate-400">Start writing to see a preview.</p>
          </div>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
