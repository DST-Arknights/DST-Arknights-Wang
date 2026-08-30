-- 棋盒 SG：使用 kitcoon 的基础动作，并接入 Chester 的船只/落水状态。
require "stategraphs/commonstates"

local events = {
  CommonHandlers.OnStep(),
  CommonHandlers.OnLocomote(true, true),
  CommonHandlers.OnSleepEx(),
  CommonHandlers.OnWakeEx(),
  CommonHandlers.OnHop(),
  CommonHandlers.OnSink(),
  CommonHandlers.OnFallInVoid(),
  EventHandler("kitcoonplaywithme", function(inst, data)
    if data ~= nil and data.target ~= nil and data.target:IsValid() and not inst.sg:HasStateTag("busy") then
      inst.sg:GoToState("playful", data)
    end
  end),
  EventHandler("start_playwithplaymate", function(inst, data)
    if data ~= nil and data.target ~= nil and data.target:IsValid() and not inst.sg:HasStateTag("busy") then
      inst.sg:GoToState("playful", data)
      data.target:PushEvent("kitcoonplaywithme", { target = inst })
    end
  end),
}

local actionhandlers = {
  ActionHandler(ACTIONS.NUZZLE, "nuzzle"),
  ActionHandler(ACTIONS.CATPLAYGROUND, "catplayground"),
  ActionHandler(ACTIONS.CATPLAYAIR, "catplayair"),
}

local function GoToIdle(inst)
  if inst.AnimState:AnimDone() then
    inst.sg:GoToState("idle")
  end
end

local states = {
  State {
    name = "idle",
    tags = { "idle", "canrotate" },
    onenter = function(inst)
      inst.Physics:Stop()
      inst.AnimState:PlayAnimation("idle_loop", true)
    end,
  },

  State {
    name = "open",
    tags = { "busy", "open" },
    onenter = function(inst)
      inst.Physics:Stop()
      if inst.components.sleeper ~= nil then
        inst.components.sleeper:WakeUp()
      end
      inst.AnimState:PlayAnimation("hiding_small", true)
    end,
  },

  State {
    name = "close",
    tags = { "busy" },
    onenter = function(inst)
      inst.AnimState:PlayAnimation("sleep_pst", false)
    end,
    events = {
      EventHandler("animover", function(inst) inst.sg:GoToState("idle") end),
    },
  },

  State {
    name = "nuzzle",
    tags = { "busy", "canrotate" },
    onenter = function(inst)
      inst.Physics:Stop()
      local leader = inst.components.follower:GetLeader()
      if leader ~= nil then
        inst:ForceFacePoint(leader.Transform:GetWorldPosition())
      end
      inst.AnimState:PlayAnimation("emote_nuzzle", false)
    end,
    events = {
      EventHandler("animover", GoToIdle),
    },
  },

  State {
    name = "playful",
    tags = { "busy", "canrotate", "playful" },
    onenter = function(inst, data)
      inst.Physics:Stop()
      if data ~= nil and data.target ~= nil and data.target:IsValid() then
        inst:ForceFacePoint(data.target.Transform:GetWorldPosition())
      end
      inst.AnimState:PlayAnimation("interact_active", false)
    end,
    events = {
      EventHandler("animover", GoToIdle),
    },
  },

  State {
    name = "catplayground",
    tags = { "busy", "canrotate", "jumping" },
    onenter = function(inst, data)
      inst.Physics:Stop()
      if data ~= nil and data.target ~= nil and data.target:IsValid() then
        inst:ForceFacePoint(data.target.Transform:GetWorldPosition())
      end
      inst.AnimState:PlayAnimation("emote_cute", false)
    end,
    events = {
      EventHandler("animover", GoToIdle),
    },
  },

  State {
    name = "catplayair",
    tags = { "busy", "canrotate", "jumping" },
    onenter = function(inst, data)
      inst.Physics:Stop()
      if data ~= nil and data.target ~= nil and data.target:IsValid() then
        inst:ForceFacePoint(data.target.Transform:GetWorldPosition())
      end
      inst.AnimState:PlayAnimation("emote_cute", false)
    end,
    events = {
      EventHandler("animover", GoToIdle),
    },
  },
}

CommonStates.AddWalkStates(states, {}, { startwalk = "walk_pre", walk = "walk_loop", stopwalk = "walk_pst" }, true)
CommonStates.AddRunStates(states, nil, { startrun = "walk_pre", run = "walk_loop", stoprun = "walk_pst" })
CommonStates.AddSleepExStates(states)
CommonStates.AddHopStates(states, true)
CommonStates.AddSinkAndWashAshoreStates(states)
CommonStates.AddVoidFallStates(states)
CommonStates.AddInitState(states, "idle")

return StateGraph("piece_box", states, events, "init", actionhandlers)