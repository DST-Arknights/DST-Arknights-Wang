-- 望的天赋配置
-- 被动【铸子】：每 interval 秒生成一枚黑子，按外挂棋盒、背包棋盒、普通背包顺序存放
-- 参考物品包 RegisterArkTalent + 重岳 chongyue_talent.lua

local PieceResource = require "wang_piece_resource"

local function GiveGeneratedPiece(inst, item)
  return PieceResource.Give(inst, item)
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
