-- 望的天赋配置
-- 被动【铸子】：每 interval 秒生成一枚黑子，按外挂棋盒、背包棋盒、普通背包顺序存放
-- 参考物品包 RegisterArkTalent + 重岳 chongyue_talent.lua

local function TryPutPieceInBox(box, item)
  -- drop_on_fail=false：棋盒已满时保留棋子，继续尝试其它目标。
  return box.components.container:GiveItem(item, nil, nil, false) == true
end

local function IsExternalPieceBox(inst, box)
  return box.components.follower:GetLeader() == inst
    and not box.components.inventoryitem:IsHeld()
end

local function GiveGeneratedPiece(inst, item)
  local inventory = inst.components.inventory

  -- 1. 先尝试外挂（跟随态）棋盒。
  local boundbox = inst.components.wang_chess_box_owner:GetBox()
  if boundbox ~= nil and boundbox:IsValid()
      and IsExternalPieceBox(inst, boundbox)
      and TryPutPieceInBox(boundbox, item) then
    return true
  end

  -- 2. 再查物品栏和装备栏中的棋盒，装备状态不影响存入。
  local boxes = inventory:FindItems(function(candidate)
    return candidate.prefab == "piece_box"
  end)
  for _, box in ipairs(boxes) do
    if TryPutPieceInBox(box, item) then
      return true
    end
  end

  -- 3. 所有棋盒都不存在或已满时，才进入普通物品栏。
  return inventory:GiveItem(item) and true or false
end

local function StartZhuzi(talent)
  if talent._zhuzi_task then
    talent._zhuzi_task:Cancel()
    talent._zhuzi_task = nil
  end
  if not talent:IsActivating() then
    return
  end

  local inst = talent.inst
  local params = talent:GetLevelParams()
  talent._zhuzi_task = inst:DoPeriodicTask(params.interval, function()
    -- 玩家死亡/幽灵等无背包时不生成
    if not inst:IsValid() or inst.components.inventory == nil then
      return
    end
    local item = SpawnPrefab("piece")
    if not GiveGeneratedPiece(inst, item) then
      item:Remove() -- 背包满：黑子消失，等下一次生成
    end
  end)
end

local function StopZhuzi(talent)
  if talent._zhuzi_task then
    talent._zhuzi_task:Cancel()
    talent._zhuzi_task = nil
  end
end

RegisterArkTalent({
  id    = "wang_talent_zhuzi",
  atlas = "images/inventoryimages/piece.xml",
  image = "piece.tex",
  name  = STRINGS.UI.ARK_TALENT.NAMES.WANG[1],
  levels = {
    {
      desc   = STRINGS.UI.ARK_TALENT.LEVEL_DESC.WANG[1][1],
      params = { interval = 20 }, -- 精英0：每 20 秒一枚
    },
    {
      desc   = STRINGS.UI.ARK_TALENT.LEVEL_DESC.WANG[1][2],
      params = { interval = 15 }, -- 精英1：每 15 秒一枚
    },
    {
      desc   = STRINGS.UI.ARK_TALENT.LEVEL_DESC.WANG[1][3],
      params = { interval = 10 }, -- 精英2：每 10 秒一枚
    },
  },
  OnActivate = StartZhuzi,
  OnLevelChange = StartZhuzi,
  OnDeactivate = StopZhuzi,
})
