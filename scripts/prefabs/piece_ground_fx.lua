local assets = {
  Asset("ANIM", "anim/piece.zip"),
}

local function fn()
  local inst = CreateEntity()

  inst.entity:AddTransform()
  inst.entity:AddAnimState()
  inst.entity:AddNetwork()

  inst:AddTag("FX")
  inst:AddTag("NOCLICK")

  inst.AnimState:SetBank("piece")
  inst.AnimState:SetBuild("piece")
  inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
  inst.AnimState:SetLayer(LAYER_BACKGROUND)
  inst.AnimState:SetSortOrder(3)

  inst.entity:SetPristine()

  if not TheWorld.ismastersim then
    return inst
  end

  inst.PlayDeploy = function(inst)
    inst.AnimState:PlayAnimation("JiHuo_DiMian-0", false)
    inst.AnimState:SetFrame(5)
    inst.AnimState:PushAnimation("JiHuo_DiMian-1", true)
  end

  inst.PlayInactive = function(inst, frame)
    if inst.AnimState:IsCurrentAnimation("JiHuo_DiMian-1") then
      return
    end
    inst.AnimState:PlayAnimation("JiHuo_DiMian-1", true)
    if frame ~= nil then
      inst.AnimState:SetFrame(frame)
    end
  end

  inst.persists = false
  return inst
end

return Prefab("piece_ground_fx", fn, assets)
