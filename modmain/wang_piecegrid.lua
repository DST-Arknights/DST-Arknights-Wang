-- ════════════════════════════════════════════════════════
-- 棋子投掷：服务端网格检查与起飞属性初始化
-- 主客机都维护本地网格缓存；客户端 CanTossInWorld O(1) 查询，服务端动作执行处再做权威检查。
-- 包一层原版 ACTIONS.TOSS.fn：黑子目标格已有棋子实体 → 不投掷、棋子不消耗（仍留在手上/堆叠）。
-- 仅对 prefab == "piece" 生效，水球/鞭炮等其它 TOSS 物品不受影响。
-- ════════════════════════════════════════════════════════
local WANG_GRID = require "wang_piecegrid"
local GetEliteBonusDamage = require "wang_piece_damage"

local PIECE_TOSS_RANGE_MULTIPLIER = 1.6
local PIECE_TOSS_SPEED_MARGIN = 0.5

-- complexprojectile 的 horizontalSpeed 实际作为抛体初速度参与弹道计算。
-- 目标过远而速度不足时原版会退化为固定 30°，导致飞行物提前落地；
-- 因此只在远投时把初速度抬到“刚好可达 + 少量余量”，近投仍保留原手感。
local function FitPieceTossSpeed(projectile, doer, targetPos)
  local complexprojectile = projectile.components.complexprojectile
  if complexprojectile == nil or targetPos == nil then
    return
  end

  local gravity = -(complexprojectile.gravity or 0)
  if gravity <= 0 then
    return
  end

  local x, _, z = doer.Transform:GetWorldPosition()
  local dx = targetPos.x - x
  local dz = targetPos.z - z
  local range = math.sqrt(dx * dx + dz * dz)
  local launchY = complexprojectile.launchoffset ~= nil and complexprojectile.launchoffset.y or 0
  local targetY = complexprojectile.targetoffset ~= nil and complexprojectile.targetoffset.y or 0
  local dy = targetY - launchY

  -- 抛体到达 (range, dy) 所需的最小初速度：v² = g * (dy + sqrt(range² + dy²))。
  local minSpeed = math.sqrt(gravity * (dy + math.sqrt(range * range + dy * dy)))
  complexprojectile:SetHorizontalSpeed(math.max(15, minSpeed + PIECE_TOSS_SPEED_MARGIN))
end

local function GetTossProjectile(doer, bufferedaction)
  local projectile = bufferedaction ~= nil and bufferedaction.invobject or nil
  if projectile ~= nil or doer == nil then
    return projectile
  end

  if doer.replica ~= nil and doer.replica.inventory ~= nil then
    return doer.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
  end
  if doer.components.inventory ~= nil then
    return doer.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
  end
end

local function InitPieceProjectile(projectile, deployer)
  projectile._baseDamage = TUNING.WANG.PIECE_BASE_DAMAGE
  projectile._eliteBonusDamage = GetEliteBonusDamage(deployer)
  projectile._damageMultiplier = 1
  projectile._explodeRangeMultiplier = 1
  projectile._neighborMode = "cross"
  projectile._deployer = deployer
  projectile._deployerUserid = deployer ~= nil and deployer.userid or nil
end

-- 原版 TOSS.distance = 8。只给黑子增加额外到达距离，使实际投掷距离变为原来的 1.6 倍；
-- 保留其它模组可能已有的 extra_arrive_dist，不影响水球等其它 TOSS 物品。
local _origTossExtraArriveDist = ACTIONS.TOSS.extra_arrive_dist
ACTIONS.TOSS.extra_arrive_dist = function(doer, dest, bufferedaction)
  local extra = _origTossExtraArriveDist ~= nil
      and (_origTossExtraArriveDist(doer, dest, bufferedaction) or 0)
      or 0
  local projectile = GetTossProjectile(doer, bufferedaction)
  if projectile ~= nil and projectile.prefab == "piece" then
    return extra + (ACTIONS.TOSS.distance or 0) * (PIECE_TOSS_RANGE_MULTIPLIER - 1)
  end
  return extra
end

local _origTossFn = ACTIONS.TOSS.fn
ACTIONS.TOSS.fn = function(act)
  if act.doer ~= nil and TheWorld.ismastersim and act.doer.components.inventory ~= nil then
    local source = act.invobject
    if source == nil then
      source = act.doer.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    end

    if source ~= nil and source.prefab == "piece" then
      if source.components.equippable ~= nil
          and (source.components.equippable:IsRestricted(act.doer)
            or source.components.equippable:ShouldPreventUnequipping()) then
        return false
      end

      local pos = act.target ~= nil and act.target:GetPosition() or act:GetActionPoint()
      if pos == nil then
        return false
      end

      local gx, gz = WANG_GRID:WorldToCell(pos.x, pos.z)
      if WANG_GRID:IsOccupied(gx, gz) then
        return false
      end

      -- 参考原版弹弓/船炮：消耗库存物品，另外生成专用飞行 prefab。
      local projectile = SpawnPrefab("piece_projectile")
      if projectile == nil then
        return false
      end

      local consumed = act.doer.components.inventory:RemoveItem(source, false)
      if consumed == nil then
        projectile:Remove()
        return false
      end
      consumed:Remove()

      InitPieceProjectile(projectile, act.doer)
      local x, y, z = act.doer.Transform:GetWorldPosition()
      projectile.Transform:SetPosition(x, y, z)
      FitPieceTossSpeed(projectile, act.doer, pos)
      projectile.components.complexprojectile:Launch(pos, act.doer)

      if act.from_map then
        act.doer:CloseMinimap()
      end
      return true
    end
  end

  return _origTossFn(act)
end
