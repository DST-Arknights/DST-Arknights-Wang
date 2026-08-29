-- ════════════════════════════════════════════════════════
-- 棋盒 brain：参考切斯特，跟随"建造者/持有者"
-- 切斯特是跟随眼骨（follower.leader 由眼骨设置）；棋盒直接跟随玩家 leader
-- （follower 组件对玩家 leader 自动存档：cached_player_leader_userid，读档自动重连）
-- 无战斗组件 → 去掉切斯特的 PanicTrigger；无据点 → 去掉 Wander
-- ════════════════════════════════════════════════════════
require "behaviours/follow"
require "behaviours/faceentity"

local MIN_FOLLOW_DIST = 0
local TARGET_FOLLOW_DIST = 6
local MAX_FOLLOW_DIST = 12

local function GetLeader(inst)
  return inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
end

local function GetFaceTargetFn(inst)
  return GetLeader(inst)
end

local function KeepFaceTargetFn(inst, target)
  return GetLeader(inst) == target
end

local ChessBoxBrain = Class(Brain, function(self, inst)
  Brain._ctor(self, inst)
end)

function ChessBoxBrain:OnStart()
  local root = PriorityNode({
    Follow(self.inst, function() return GetLeader(self.inst) end, MIN_FOLLOW_DIST, TARGET_FOLLOW_DIST, MAX_FOLLOW_DIST),
    FaceEntity(self.inst, GetFaceTargetFn, KeepFaceTargetFn),
  }, .25)
  self.bt = BT(self.inst, root)
end

return ChessBoxBrain
