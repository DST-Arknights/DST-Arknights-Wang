-- ════════════════════════════════════════════════════════
-- 棋盒 SG（类切斯特结构，动画用 catcoon 占位）
-- 打开/关闭：catcoon 无"开盖"动画，暂用 taunt(仰起) 作打开、idle 作关闭
--           （后续切换棋盒 build 时替换成正式 open/close 动画）
-- 行走：复用 CommonStates.AddWalkStates（walk_pre/walk_loop/walk_pst）
-- ════════════════════════════════════════════════════════
require "stategraphs/commonstates"

local events = {
  CommonHandlers.OnStep(),
  CommonHandlers.OnLocomote(false, true),
}

local states = {
  State {
    name = "idle",
    tags = { "idle", "canrotate" },
    onenter = function(inst)
      inst.Physics:Stop()
      inst.AnimState:PlayAnimation("idle_loop", true)
    end,
  },

  -- 打开（容器 onopenfn 触发）
  State {
    name = "open",
    tags = { "busy", "open" },
    onenter = function(inst)
      inst.Physics:Stop()
      inst.AnimState:PlayAnimation("taunt") -- 占位：仰起 = 开盖
    end,
    events = {
      EventHandler("animover", function(inst) inst.sg:GoToState("open_idle") end),
    },
  },

  -- 打开待机（容器 UI 开启期间循环）
  State {
    name = "open_idle",
    tags = { "busy", "open" },
    onenter = function(inst)
      inst.AnimState:PlayAnimation("idle_loop", true)
    end,
  },

  -- 关闭（容器 onclosefn 触发）
  State {
    name = "close",
    tags = { "busy" },
    onenter = function(inst)
      inst.AnimState:PlayAnimation("idle")
    end,
    events = {
      EventHandler("animover", function(inst) inst.sg:GoToState("idle") end),
    },
  },
}

CommonStates.AddWalkStates(states, {}, { startwalk = "walk_pre", walk = "walk_loop", stopwalk = "walk_pst" }, true)
CommonStates.AddInitState(states, "idle")

return StateGraph("piece_box", states, events, "init")
