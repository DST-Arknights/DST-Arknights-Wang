-- 棋盒 brain：融合 Chester 的永久跟随与 kitcoon 的互动/规避行为。
require "behaviours/follow"
require "behaviours/faceentity"
require "behaviours/panic"
require "behaviours/runaway"
require "behaviours/doaction"
require "behaviours/wander"
local BrainCommon = require "brains/braincommon"

local MIN_FOLLOW_DIST = 0
local TARGET_FOLLOW_DIST = 2.5
local MAX_FOLLOW_DIST = 4.5
local PLAYFUL_FIND_DIST = 4
local PLAYFUL_KEEP_DIST = 8
local COMBAT_TOO_CLOSE_DIST = 5
local COMBAT_SAFE_DIST = 8
local SCARY_DIST = 6
local SCARY_STOP_DIST = 10

local function GetLeader(inst)
  return inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
end

local function GetFaceTargetFn(inst)
  return GetLeader(inst)
end

local function KeepFaceTargetFn(inst, target)
  return GetLeader(inst) == target
end

local function NuzzleOwner(inst)
  local leader = GetLeader(inst)
  if leader == nil or leader:HasTag("playerghost") or inst.sg:HasStateTag("busy") then
    return nil
  end
  if GetTime() < (inst._next_nuzzle_time or 0) or math.random() > 0.05 then
    return nil
  end
  inst._next_nuzzle_time = GetTime() + (TUNING.CRITTER_NUZZLE_DELAY or 120)
  return BufferedAction(inst, leader, ACTIONS.NUZZLE)
end

local function CanPlayWith(target, owner)
  return target ~= owner and target:IsValid() and target:HasTag("kitcoon")
    and not target:HasTag("busy") and target:IsOnPassablePoint()
    and (target.components.sleeper == nil or not target.components.sleeper:IsAsleep())
end

local function FindPlaymate(inst)
  local owner = GetLeader(inst)
  if owner ~= nil and owner.components.locomotor ~= nil
      and owner.components.locomotor:WantsToMoveForward() then
    return nil
  end
  local center = owner or inst
  return FindEntity(center, PLAYFUL_FIND_DIST,
    function(ent) return CanPlayWith(ent, owner or inst) end,
    nil, { "busy" }, { "kitcoon" })
end

local function ShouldPlayWithPlaymate(inst)
  if GetTime() < (inst._next_play_time or 0) or inst.sg:HasStateTag("busy") then
    return false
  end
  inst._playmate_target = FindPlaymate(inst)
  return inst._playmate_target ~= nil
end

local function StartPlaymate(inst)
  local target = inst._playmate_target or FindPlaymate(inst)
  inst._playmate_target = nil
  if target ~= nil then
    inst._next_play_time = GetTime() + (TUNING.KITCOON_PLAY_DELAY or 30)
    target:PushEvent("kitcoonplaywithme", { target = inst })
    inst:PushEvent("start_playwithplaymate", { target = target })
  end
end

local function PlayWithToy(inst)
  if GetTime() < (inst._next_play_time or 0) or inst.sg:HasStateTag("busy") then
    return nil
  end
  local target = FindEntity(inst, 4,
    function(item) return item:IsOnPassablePoint() end,
    nil,
    { "FX", "NOCLICK", "DECOR", "INLIMBO", "stump", "burnt", "notarget", "flight", "fire", "irreplaceable" },
    { "cattoy", "cattoyairborne", "catfood" })
  if target == nil then
    return nil
  end
  inst._next_play_time = GetTime() + (TUNING.KITCOON_PLAY_DELAY or 30)
  local action = target:HasTag("cattoyairborne") and ACTIONS.CATPLAYAIR or ACTIONS.CATPLAYGROUND
  return BufferedAction(inst, target, action)
end

local function CombatAvoidance(inst, target)
  local leader = GetLeader(inst)
  local combat = leader ~= nil and leader.components.combat or nil
  local targetcombat = target.components.combat
  if combat == nil or targetcombat == nil then
    return false
  end
  local distance = leader:GetDistanceSqToInst(target)
  return targetcombat:TargetIs(leader)
    or (targetcombat:HasTarget() and distance < COMBAT_TOO_CLOSE_DIST * COMBAT_TOO_CLOSE_DIST)
    or (combat:IsRecentTarget(target) and (combat.lastdoattacktime or 0) + 6 > GetTime())
end

local PieceBoxBrain = Class(Brain, function(self, inst)
  Brain._ctor(self, inst)
end)

function PieceBoxBrain:OnStart()
  local root = PriorityNode({
    BrainCommon.PanicTrigger(self.inst),
    RunAway(self.inst, { tags = { "_combat", "_health" }, notags = { "wall", "INLIMBO" }, fn = function(target) return CombatAvoidance(self.inst, target) end }, COMBAT_TOO_CLOSE_DIST, COMBAT_SAFE_DIST),
    RunAway(self.inst, { tags = { "scarytoprey" }, notags = { "player" } }, SCARY_DIST, SCARY_STOP_DIST),
    WhileNode(function() return ShouldPlayWithPlaymate(self.inst) end, "Playful", ActionNode(function() StartPlaymate(self.inst) end, "playwithplaymate")),
    Follow(self.inst, function() return GetLeader(self.inst) end, MIN_FOLLOW_DIST, TARGET_FOLLOW_DIST, MAX_FOLLOW_DIST, true),
    DoAction(self.inst, NuzzleOwner, "nuzzle", false, 5),
    DoAction(self.inst, PlayWithToy, "play", false, 5),
    FailIfRunningDecorator(FaceEntity(self.inst, GetFaceTargetFn, KeepFaceTargetFn)),
    Wander(self.inst, nil, nil, { minwalktime = 2, randwalktime = 3, minwaittime = 5, randwaittime = 8 }),
  }, .25)
  self.bt = BT(self.inst, root)
end

return PieceBoxBrain