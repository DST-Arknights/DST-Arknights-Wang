-- ════════════════════════════════════════════════════════
-- 棋子投掷：服务端网格检查与起飞属性初始化
-- 主客机都维护本地网格缓存；客户端 CanTossInWorld O(1) 查询，服务端动作执行处再做权威检查。
-- 包一层原版 ACTIONS.TOSS.fn：黑子目标格已有棋子实体 → 不投掷、棋子不消耗（仍留在手上/堆叠）。
-- 仅对 prefab == "piece" 生效，水球/鞭炮等其它 TOSS 物品不受影响。
-- ════════════════════════════════════════════════════════
local WANG_GRID = require "wang_piecegrid"
local GetEliteBonusDamage = require "wang_piece_damage"

local function OnPieceTossLaunch(inst, data)
  local deployer = data.deployer
  inst._baseDamage = TUNING.WANG.PIECE_BASE_DAMAGE
  inst._eliteBonusDamage = GetEliteBonusDamage(deployer)
  inst._damageMultiplier = 1
  inst._explodeRangeMultiplier = 1
  inst._neighborMode = "cross"
  inst._deployer = deployer
  inst._deployerUserid = deployer ~= nil and deployer.userid or nil
end

AddPrefabPostInit("piece", function(inst)
  if TheWorld.ismastersim then
    inst:ListenForEvent("wang_piece_toss_launch", OnPieceTossLaunch)
  end
end)

local _origTossFn = ACTIONS.TOSS.fn
ACTIONS.TOSS.fn = function(act)
  if act.doer ~= nil and TheWorld.ismastersim then
    local projectile = act.invobject
    if projectile == nil and act.doer.components.inventory ~= nil then
      projectile = act.doer.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    end
    if projectile ~= nil and projectile.prefab == "piece" then
      local pos = act:GetActionPoint()
      if pos ~= nil then
        local gx, gz = WANG_GRID:WorldToCell(pos.x, pos.z)
        if WANG_GRID:IsOccupied(gx, gz) then
          return false
        end
      end
    end
  end
  return _origTossFn(act)
end
