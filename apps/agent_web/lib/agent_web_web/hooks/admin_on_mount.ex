# # lib/agent_web_web/hooks/admin_on_mount.ex
# defmodule AgentWebWeb.Hooks.AdminOnMount do
#   import Phoenix.LiveView

#   def on_mount(:default, _params, session, socket) do
#     sidebar_collapsed = Map.get(session, "sidebar_collapsed", "false") == "true"

#     {:cont,
#      socket
#      |> assign(
#        sidebar_collapsed: sidebar_collapsed,
#        current_page: :dashboard,
#        current_section: :analytics,
#        is_mobile?: false
#      )}
#   end
# end
