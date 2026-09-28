-- 望的天赋配置
-- 【铸子】：周期生成黑子
-- 【应劫】：已落黑子提供减伤；致命保护由等级 params 开关控制
-- 参考物品包 RegisterArkTalent + 重岳 chongyue_talent.lua
table.insert(Assets, Asset("ATLAS", "images/wang_talent.xml"))

local PieceResource = require "wang_piece_resource"
local PieceLimit = require "wang_piece_limit"

local function GiveGeneratedPiece(inst, item)
  return PieceResource.Give(inst, item)
end

local function FormatNumber(value)
  return string.format("%g", value or 0)
end

local function FormatPercent(value)
  return FormatNumber((value or 0) * 100)
end

local function WangZhuziDesc(talent)
  local params = talent:GetLevelParams()
  return string.format(STRINGS.UI.ARK_TALENT.LEVEL_DESC.WANG[1], FormatNumber(params.interval))
end

local function WangYingjieDesc(talent)
  local params = talent:GetLevelParams()
  local reduction = FormatPercent(params.damageReductionPerPiece)
  if params.lethalProtection then
    return string.format(
      STRINGS.UI.ARK_TALENT.LEVEL_DESC.WANG[2][2],
      reduction,
      FormatNumber(params.carriedCost),
      FormatNumber(params.guardDuration)
    )
  end
  return string.format(STRINGS.UI.ARK_TALENT.LEVEL_DESC.WANG[2][1], reduction)
end

local function StartZhuzi(talent)
  if talent._zhuzi_task then
    talent._zhuzi_task:Cancel()
    talent._zhuzi_task = nil
  end
  if not talent:IsUnlocked() then
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
  atlas = "images/wang_talent.xml",
  image = "talent_1.tex",
  name  = STRINGS.UI.ARK_TALENT.NAMES.WANG[1],
  levels = {
    {
      desc   = WangZhuziDesc,
      params = { interval = 20 }, -- 精英0：每 20 秒一枚
    },
    {
      desc   = WangZhuziDesc,
      params = { interval = 15 }, -- 精英1：每 15 秒一枚
    },
    {
      desc   = WangZhuziDesc,
      params = { interval = 10 }, -- 精英2：每 10 秒一枚
    },
  },
  OnUnlocked = StartZhuzi,
  OnLevelChange = StartZhuzi,
  OnLocked = StopZhuzi,
})

local YINGJIE_ABSORB_KEY = "wang_yingjie"

local function PlayYingjieShieldHit(talent)
  local fx = talent._yingjie_fx
  if fx ~= nil and fx:IsValid() then
    fx.AnimState:PlayAnimation("hit")
    fx.AnimState:PushAnimation("idle_loop")
  end
end

local function StopYingjieGuard(talent)
  if talent._yingjie_guard_task ~= nil then
    talent._yingjie_guard_task:Cancel()
    talent._yingjie_guard_task = nil
  end
  talent._yingjie_guard_active = nil
  if talent._yingjie_fx ~= nil then
    if talent._yingjie_fx:IsValid() and talent._yingjie_fx.kill_fx ~= nil then
      talent._yingjie_fx:kill_fx()
    end
    talent._yingjie_fx = nil
  end
end

local function StartYingjieGuard(talent, duration)
  StopYingjieGuard(talent)
  talent._yingjie_guard_active = true

  local inst = talent.inst
  local fx = SpawnPrefab("forcefieldfx")
  if fx ~= nil then
    fx.entity:SetParent(inst.entity)
    fx.Transform:SetPosition(0, 0.2, 0)
    talent._yingjie_fx = fx
    PlayYingjieShieldHit(talent)
  end

  talent._yingjie_guard_task = inst:DoTaskInTime(duration, function()
    talent._yingjie_guard_task = nil
    talent._yingjie_guard_active = nil
    if talent._yingjie_fx ~= nil then
      if talent._yingjie_fx:IsValid() and talent._yingjie_fx.kill_fx ~= nil then
        talent._yingjie_fx:kill_fx()
      end
      talent._yingjie_fx = nil
    end
  end)
end

local function RefreshYingjieDamageReduction(talent)
  local health = talent.inst.components.health
  if health == nil then
    return
  end
  if not talent:IsUnlocked() then
    health.externalabsorbmodifiers:RemoveModifier(talent, YINGJIE_ABSORB_KEY)
    return
  end

  local params = talent:GetLevelParams()
  local count = PieceLimit:GetCount(talent.inst)
  local reduction = math.min(count * (params.damageReductionPerPiece or 0), params.maxDamageReduction or 1)
  health.externalabsorbmodifiers:SetModifier(talent, reduction, YINGJIE_ABSORB_KEY)
end

local function TryConsumeYingjieResource(talent, params)
  if PieceLimit:ConsumeOne(talent.inst) then
    return true
  end
  local carriedCost = params.carriedCost or 0
  return carriedCost > 0 and PieceResource.TryConsume(talent.inst, carriedCost)
end

local function IsYingjieLethal(health, amount, ignore_invincible, afflicter, ignore_absorb)
  if amount >= 0 or ignore_absorb or health.currenthealth <= 0 or (health.minhealth or 0) > 0 then
    return false
  end
  if not ignore_invincible and (health:IsInvincible() or health.inst.is_teleporting) then
    return false
  end

  local projected = amount
  local absorb = health.playerabsorb ~= 0
      and afflicter ~= nil
      and afflicter:HasTag("player")
      and health.playerabsorb + health.absorb
      or health.absorb
  projected = projected
      * math.clamp(1 - absorb, 0, 1)
      * math.max(1 - health.externalabsorbmodifiers:Get(), 0)

  if health.maxdamagetakenperhit ~= nil
      and projected < health.maxdamagetakenperhit
      and not health._ignore_maxdamagetakenperhit then
    projected = health.maxdamagetakenperhit
  end
  return health.currenthealth + projected <= 0
end

local function OnYingjieInstall(talent)
  local inst = talent.inst
  local health = inst.components.health
  if health == nil then
    return
  end

  -- externalabsorbmodifiers 会在 health.redirect 之后结算，因此致命判断前先按当前落子数刷新减伤。
  -- redirect 不是函数成员，无法走 HookFunctionWhileUnlocked；这里只安装一次代理，锁定时直接旁路。
  talent._yingjie_previous_redirect = health.redirect
  talent._yingjie_redirect = function(player, amount, overtime, cause, ignore_invincible, afflicter, ignore_absorb)
    local previous = talent._yingjie_previous_redirect
    if previous ~= nil and previous(player, amount, overtime, cause, ignore_invincible, afflicter, ignore_absorb) then
      return true
    end
    if not talent:IsUnlocked() or amount >= 0 or ignore_absorb then
      return false
    end

    RefreshYingjieDamageReduction(talent)

    if talent._yingjie_guard_active then
      PlayYingjieShieldHit(talent)
      return true
    end

    local params = talent:GetLevelParams()
    if not params.lethalProtection
        or not IsYingjieLethal(health, amount, ignore_invincible, afflicter, ignore_absorb)
        or not TryConsumeYingjieResource(talent, params) then
      return false
    end

    StartYingjieGuard(talent, params.guardDuration or 0)
    return true
  end
  health.redirect = talent._yingjie_redirect

  -- 保护窗口内的普通战斗攻击在护甲结算前直接挡掉；解锁/锁定/读档生命周期交给框架。
  if inst.components.combat ~= nil then
    talent:HookFunctionWhileUnlocked(inst.components.combat, "GetAttacked", function(next, self, ...)
      if talent._yingjie_guard_active then
        PlayYingjieShieldHit(talent)
        return true
      end
      return next(self, ...)
    end)
  end
end

local function OnYingjieUnlocked(talent)
  RefreshYingjieDamageReduction(talent)
end

local function OnYingjieLevelChange(talent)
  RefreshYingjieDamageReduction(talent)
  if not talent:GetLevelParams().lethalProtection then
    StopYingjieGuard(talent)
  end
end

local function OnYingjieLocked(talent)
  StopYingjieGuard(talent)
  local health = talent.inst.components.health
  if health ~= nil then
    health.externalabsorbmodifiers:RemoveModifier(talent, YINGJIE_ABSORB_KEY)
  end
end

local function OnYingjieRemove(talent)
  OnYingjieLocked(talent)
  local health = talent.inst.components.health
  if health ~= nil and health.redirect == talent._yingjie_redirect then
    health.redirect = talent._yingjie_previous_redirect
  end
  talent._yingjie_redirect = nil
  talent._yingjie_previous_redirect = nil
end

RegisterArkTalent({
  id    = "wang_talent_yingjie",
  atlas = "images/wang_talent.xml",
  image = "talent_2.tex", -- 暂用第一天赋图标
  name  = STRINGS.UI.ARK_TALENT.NAMES.WANG[2],
  levels = {
    {
      desc = WangYingjieDesc,
      params = {
        damageReductionPerPiece = 0.005,
        maxDamageReduction = 0.9,
        lethalProtection = false,
      },
    },
    {
      desc = WangYingjieDesc,
      params = {
        damageReductionPerPiece = 0.005,
        maxDamageReduction = 0.9,
        lethalProtection = true,
        carriedCost = 3,
        guardDuration = 1.5,
      },
    },
  },
  OnInstall = OnYingjieInstall,
  OnUnlocked = OnYingjieUnlocked,
  OnLevelChange = OnYingjieLevelChange,
  OnLocked = OnYingjieLocked,
  OnRemove = OnYingjieRemove,
})
