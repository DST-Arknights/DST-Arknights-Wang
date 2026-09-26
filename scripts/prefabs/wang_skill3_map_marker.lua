-- 天下劫地图聚合点专用全局标记。
--
-- 不能直接复用 globalmapicon：原版 globalmapicon 只有 proxy 图层，
-- 引擎会在目标进入近端同步/可见范围时隐藏 proxy，原版依赖真实实体自己的 MiniMapEntity 接替显示。
-- 聚合点没有对应真实实体，因此同时创建 near(非 proxy) + far(proxy) 两层，
-- 与新版 globaltrackingicon 的实现保持一致，保证近处/远处、已探索/迷雾区域都能显示。

local MAP_ICON_BUCKET = "wang_skill3_map_marker"
local MAP_ICON_TEXTURE = "piece.tex"
local MAP_ICON_PRIORITY = 20

local function CreateIcon(parent, isproxy)
  local icon = CreateEntity()
  icon:AddTag("CLASSIFIED")
  icon.persists = false

  icon.entity:AddTransform()
  icon.entity:AddMiniMapEntity()

  icon.MiniMapEntity:SetIcon(MAP_ICON_TEXTURE)
  icon.MiniMapEntity:SetPriority(MAP_ICON_PRIORITY)
  icon.MiniMapEntity:SetCanUseCache(false)
  icon.MiniMapEntity:SetDrawOverFogOfWar(true)
  icon.MiniMapEntity:SetIsProxy(isproxy)
  icon.entity:SetParent(parent.entity)
  return icon
end

local function InitIcons(inst)
  if inst._wang_skill3_icon_near ~= nil then
    return
  end
  inst._wang_skill3_icon_near = CreateIcon(inst, false)
  inst._wang_skill3_icon_far = CreateIcon(inst, true)
end

local function fn()
  local inst = CreateEntity()

  inst.entity:AddTransform()
  inst.entity:AddNetwork()

  inst:AddTag("CLASSIFIED")
  inst:AddTag("globalmapicon")
  inst:AddTag("wang_skill3_map_marker")
  inst.entity:SetCanSleep(false)

  -- 使用专用 bucket，地图选择器不需要扫描所有原版 globalmapicon。
  RegisterGlobalMapIcon(inst, MAP_ICON_BUCKET)

  inst.entity:SetPristine()

  if not TheNet:IsDedicated() then
    InitIcons(inst)
  end

  if not TheWorld.ismastersim then
    return inst
  end

  inst.persists = false
  return inst
end

return Prefab("wang_skill3_map_marker", fn)
