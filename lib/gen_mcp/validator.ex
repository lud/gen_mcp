defmodule GenMcp.Validator do
  alias JSV.Ref
  require GenMcp.Entities.ModMap, as: ModMap
  ModMap.require_all()

  ctx = JSV.build_init!(formats: true)
  {:root, _, ctx} = JSV.build_add!(ctx, ModMap)

  key! = fn ctx, name -> JSV.build_key!(ctx, Ref.pointer!(["definitions", name], :root)) end

  {client_request, ctx} = key!.(ctx, "ClientRequest")
  {client_notif, ctx} = key!.(ctx, "ClientNotification")

  @root JSV.to_root!(ctx, :root)
  @client_request client_request
  @client_notif client_notif

  defp root do
    @root
  end

  def validate_request(request) do
    JSV.validate(request, root(), key: @client_request)
  end

  def validate_notification(notif) do
    JSV.validate(notif, root(), key: @client_notif)
  end
end
