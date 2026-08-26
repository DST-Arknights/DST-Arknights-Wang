-- ════════════════════════════════════════════════════════
-- 棋子网格：服务端 TOSS 权威拦截
-- 客户端 CanTossInWorld 只做 UI 门禁（看不到飞行中的占位）；真正拦截在动作执行处。
-- 包一层原版 ACTIONS.TOSS.fn：黑子目标格被占/被占位 → 不投掷、棋子不消耗（仍留在手上/堆叠）。
-- 仅对 prefab == "piece" 生效，水球/鞭炮等其它 TOSS 物品不受影响。
-- ════════════════════════════════════════════════════════
local WANG_GRID = require "wang_piecegrid"

local _origTossFn = ACTIONS.TOSS.fn
ACTIONS.TOSS.fn = function(act)
  if act.doer ~= nil and TheWorld.ismastersim then
    local projectile = act.invobject
    if projectile == nil and act.doer.components.inventory ~= nil then
      projectile = act.doer.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    end
    if projectile ~= nil and projectile.prefab == "piece" then
      local pos = act:GetActionPoint()
      if pos ~= nil and WANG_GRID:IsCellTaken(pos.x, pos.z) then
        return false
      end
    end
  end
  return _origTossFn(act)
end
