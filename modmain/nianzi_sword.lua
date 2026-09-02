-- ════════════════════════════════════════════════════════
-- 拈子剑：右键落子动作
-- 链路：装备剑右键点击可通行地面 → POINT collector 生成 WANG_LUOZI
--       → sg:wang_luozi 播剑攻击动画(atk_pre/atk) → Frame 7 执行 fn
--       → fn 消耗背包一枚黑子，目标点生成部署态棋子（播 ChuXian 出现动画）
-- 施法距离：action.distance = 15（玩家会走近到 15 格内执行）
-- 网格：落点格已被占/被占位 → 不显示动作（客户端）/ 不消耗不部署（服务端 fn 权威）
-- ════════════════════════════════════════════════════════
local Grid = require "wang_piecegrid"
local PieceResource = require "wang_piece_resource"

-- 落子 action：fn 从 act:GetActionPoint() 读取目标地面点，消耗黑子并部署棋子
AddAction("WANG_LUOZI", STRINGS.ACTIONS.WANG_LUOZI, function(act)
  local doer = act.doer
  local pos = act:GetActionPoint()
  if doer == nil or pos == nil then
    return false
  end
  -- 无黑子则失败（不消耗，返回失败原因）
  if not PieceResource.HasAny(doer) then
    return false, "NO_PIECES"
  end
  -- 网格检查：落点格已被占/被占位 → 不消耗不部署
  if Grid:IsCellTaken(pos.x, pos.z) then
    return false, "CELL_OCCUPIED"
  end
  if not PieceResource.TryConsume(doer, 1) then
    return false, "NO_PIECES"
  end
  local sx, sz = Grid:SnapPos(pos.x, pos.z) -- 吸附 ON → 格中心
  local skill = doer.components.ark_skill ~= nil
      and doer.components.ark_skill:GetSkill("wang_skill3") or nil
  local deploydata = { playappear = true }
  if skill ~= nil and skill:IsActivating() then
    deploydata.damageMultiplier = 2
    deploydata.explodeRangeMultiplier = 2
  end
  local piece = SpawnPrefab("piece")
  piece:DeployPiece(Vector3(sx, pos.y, sz), deploydata)
  if skill ~= nil and skill:IsActivating() then
    doer:PushEvent("wang_skill3_manual_deploy", { x = sx, y = pos.y, z = sz })
  end
  return true
end)
ACTIONS.WANG_LUOZI.distance = 15 -- 施法 / 走近距离
ACTIONS.WANG_LUOZI.rmb = true

-- POINT 采集器：装备拈子剑（含 nianzi_sword 组件）右键点击可通行地面时生成落子动作
-- 背包有黑子 + 落点格空闲才显示；客户端通过 replica.inventory / IsCellTakenForAction 判断
AddComponentAction("POINT", "nianzi_sword", function(inst, doer, pos, actions, right, target)
  if right
      and doer ~= nil and not doer:HasTag("playerghost")
      and PieceResource.HasAny(doer)
      and TheWorld.Map ~= nil and not TheWorld.Map:IsGroundTargetBlocked(pos)
      and not Grid:IsCellTakenForAction(pos.x, pos.z) then
    table.insert(actions, ACTIONS.WANG_LUOZI)
  end
end)

-- 落子 sg（wilson / wilson_client 共享）：
-- 播剑普通攻击挥一下（atk_pre → atk），Frame 7 执行落子
-- 结束用 FrameEvent（不用 animover，避免 atk_pre 播完即退）
-- TODO: 帧数待剑动画确定后微调
local wangLuoziState = State {
  name = "wang_luozi",
  tags = { "doing", "busy" },
  server_states = { "wang_luozi" },
  onenter = function(inst, data)
    local action = inst:GetBufferedAction()
    if action ~= nil and not TheWorld.ismastersim then
      inst:PerformPreviewBufferedAction()
    end
    inst.components.locomotor:Stop()
    inst.AnimState:PlayAnimation("atk_pre")
    inst.AnimState:PushAnimation("atk", false)
    if action ~= nil and action.pos ~= nil then
      inst:ForceFacePoint(action:GetActionPoint():Get())
    end
  end,
  timeline = {
    FrameEvent(7, function(inst)
      if not TheWorld.ismastersim then
        return
      end
      inst:PerformBufferedAction()
    end),
    FrameEvent(15, function(inst) inst.sg:GoToState("idle") end),
  },
}
AddStategraphState("wilson", wangLuoziState)
AddStategraphState("wilson_client", wangLuoziState)
AddStategraphActionHandler("wilson", ActionHandler(ACTIONS.WANG_LUOZI, "wang_luozi"))
AddStategraphActionHandler("wilson_client", ActionHandler(ACTIONS.WANG_LUOZI, "wang_luozi"))
