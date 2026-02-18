defmodule NexusWeb.ProjectLive.Settings do
  use NexusWeb, :live_view

  alias Nexus.Content.Templates.Registry

  on_mount {NexusWeb.LiveUserAuth, :live_user_required}
  on_mount {NexusWeb.ProjectScope, :default}

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.project
    user = socket.assigns.current_user

    form =
      project
      |> AshPhoenix.Form.for_update(:update, actor: user)
      |> to_form()

    {:ok,
     socket
     |> assign(:page_title, "#{project.name} - Settings")
     |> assign(:all_templates, Registry.all())
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    params = params |> convert_locales_param() |> convert_templates_param()

    form =
      socket.assigns.project
      |> AshPhoenix.Form.for_update(:update,
        params: params,
        actor: socket.assigns.current_user
      )
      |> AshPhoenix.Form.validate(params)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    params = params |> convert_locales_param() |> convert_templates_param()

    case AshPhoenix.Form.for_update(socket.assigns.project, :update,
           params: params,
           actor: socket.assigns.current_user
         )
         |> AshPhoenix.Form.submit() do
      {:ok, project} ->
        {:noreply,
         socket
         |> assign(:project, project)
         |> put_flash(:info, "Project updated successfully")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  @impl true
  def handle_event(event, params, socket)
      when event in ~w(reorder_tree_item start_creating_page start_creating_folder cancel_inline_create save_inline_content) do
    NexusWeb.ContentTreeHandlers.handle_event(event, params, socket)
  end

  defp convert_templates_param(params) do
    case params["available_templates"] do
      templates when is_map(templates) ->
        selected =
          templates
          |> Enum.filter(fn {_k, v} -> v == "true" end)
          |> Enum.map(fn {k, _v} -> k end)

        # Always include "default"
        selected = if "default" in selected, do: selected, else: ["default" | selected]
        Map.put(params, "available_templates", selected)

      _ ->
        params
    end
  end

  defp convert_locales_param(params) do
    case params["available_locales"] do
      locales when is_binary(locales) ->
        locales_list =
          locales
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        Map.put(params, "available_locales", locales_list)

      _ ->
        params
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.project
      flash={@flash}
      project={@project}
      project_role={@project_role}
      sidebar_folders={@sidebar_folders}
      sidebar_pages={@sidebar_pages}
      creating_content_type={@creating_content_type}
      breadcrumbs={[{"Settings", nil}]}
    >
      <div class="p-6 max-w-xl">
        <h1 class="text-2xl font-bold mb-8">Project Settings</h1>

        <.form
          for={@form}
          id="project-settings-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <.input field={@form[:name]} label="Name" required />
          <.input field={@form[:description]} label="Description" type="textarea" />
          <.input field={@form[:default_locale]} label="Default Locale" required />
          <.input
            field={@form[:available_locales]}
            label="Available Locales"
            type="text"
            value={Enum.join(@form[:available_locales].value || [], ", ")}
            required
          />
          <p class="text-xs text-base-content/50 -mt-2">
            Comma-separated list of locale codes (e.g., en, de, fr, es)
          </p>
          <.input field={@form[:is_public]} label="Public" type="checkbox" />
          <div>
            <span class="text-sm font-medium">Available Templates</span>
            <p class="text-xs text-base-content/50 mb-2">
              Select which templates are available for pages in this project.
            </p>
            <div class="space-y-2">
              <label
                :for={{slug, template} <- @all_templates}
                class="flex items-center gap-2 cursor-pointer"
              >
                <input
                  type="hidden"
                  name={"form[available_templates][#{slug}]"}
                  value="false"
                />
                <input
                  type="checkbox"
                  name={"form[available_templates][#{slug}]"}
                  value="true"
                  checked={slug in (@form[:available_templates].value || [])}
                  disabled={slug == "default"}
                  class="checkbox checkbox-sm checkbox-primary"
                />
                <span class="text-sm">{template.label}</span>
                <span :if={template.description} class="text-xs text-base-content/50">
                  - {template.description}
                </span>
              </label>
            </div>
          </div>
          <div class="flex justify-end mt-6">
            <.button type="submit" class="btn btn-primary" phx-disable-with="Saving...">
              Save Changes
            </.button>
          </div>
        </.form>
      </div>
    </Layouts.project>
    """
  end
end
