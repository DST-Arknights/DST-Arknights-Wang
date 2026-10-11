-- 隐藏搬运体力：按实际持有时间结算，只在耗尽、解锁或回满时安排任务。
local WangCarryStamina = Class(function(self, inst)
  self.inst = inst
  self.stamina = TUNING.WANG.CARRY_DURATION
  self.rest = 0
  self._carrying = false
  self._lasttime = GetTime()
  self._task = nil

  self._onstatechanged = function()
    -- inventory 读档会重新装备重物；此时不能提前禁搬或放下。
    if not inst.components.inventory.isloading then
      self:Refresh()
    end
  end
  inst:ListenForEvent("equip", self._onstatechanged)
  inst:ListenForEvent("unequip", self._onstatechanged)
  inst:ListenForEvent("mounted", self._onstatechanged)
  inst:ListenForEvent("dismounted", self._onstatechanged)
  -- 旧存档没有本组件数据，也需在 inventory 恢复后接管搬运。
  self._task = inst:DoTaskInTime(0, function()
    self._task = nil
    self:Refresh()
  end)
end)

function WangCarryStamina:UpdateStamina()
  local now = GetTime()
  local elapsed = now - self._lasttime
  self._lasttime = now
  if self._carrying then
    self.stamina = math.max(0, self.stamina - elapsed)
  else
    local recovery = TUNING.WANG.CARRY_DURATION / TUNING.WANG.CARRY_RECOVERY_TIME
    self.stamina = math.min(TUNING.WANG.CARRY_DURATION, self.stamina + elapsed * recovery)
    self.rest = math.max(0, self.rest - elapsed)
  end
end

function WangCarryStamina:CancelTask()
  if self._task ~= nil then
    self._task:Cancel()
    self._task = nil
  end
end

function WangCarryStamina:ScheduleUpdate()
  self:CancelTask()
  local delay
  if self._carrying then
    delay = self.stamina
  elseif self.rest > 0 then
    delay = self.rest
  elseif self.stamina < TUNING.WANG.CARRY_DURATION then
    delay = (TUNING.WANG.CARRY_DURATION - self.stamina)
      * TUNING.WANG.CARRY_RECOVERY_TIME / TUNING.WANG.CARRY_DURATION
  end
  if delay ~= nil then
    self._task = self.inst:DoTaskInTime(delay, function()
      self._task = nil
      self:Refresh()
    end)
  end
end

function WangCarryStamina:Refresh()
  self:UpdateStamina()
  local inventory = self.inst.components.inventory
  local riding = self.inst.components.rider:IsRiding()
  local carrying = inventory:IsHeavyLifting() and not riding

  -- 先结算上一段搬运；临界时主动放下或上牛也不能免掉耗尽休息。
  if (self._carrying or carrying) and self.stamina <= 0 and self.rest <= 0 then
    self.rest = TUNING.WANG.CARRY_EXHAUSTED_REST
  end
  inventory.noheavylifting = not riding and (self.rest > 0 or self.stamina <= 0)
  self._carrying = carrying and not inventory.noheavylifting

  if carrying and inventory.noheavylifting then
    inventory:DropItem(inventory:GetEquippedItem(EQUIPSLOTS.BODY), true, true)
    self.inst.components.talker:Say(STRINGS.CHARACTERS.WANG.ANNOUNCE.WANG_CARRY_EXHAUSTED)
  end
  -- DropItem 会同步触发 unequip；重新安排时会取消该回调创建的任务。
  self:ScheduleUpdate()
end

function WangCarryStamina:OnSave()
  self:UpdateStamina()
  -- 同一帧可能先存档、后执行耗尽任务；先保存休息锁，避免读档短暂再搬。
  if self._carrying and self.stamina <= 0 and self.rest <= 0 then
    self.rest = TUNING.WANG.CARRY_EXHAUSTED_REST
  end
  return { stamina = self.stamina, rest = self.rest }
end

function WangCarryStamina:OnLoad(data)
  if data ~= nil then
    self.stamina = math.clamp(data.stamina or TUNING.WANG.CARRY_DURATION, 0, TUNING.WANG.CARRY_DURATION)
    self.rest = math.clamp(data.rest or 0, 0, TUNING.WANG.CARRY_EXHAUSTED_REST)
  end
  self._carrying = false
  self._lasttime = GetTime()
  self:CancelTask()
  -- 等所有组件（尤其 inventory、rider）完成恢复后，再统一应用限制。
  self._task = self.inst:DoTaskInTime(0, function()
    self._task = nil
    self:Refresh()
  end)
end

function WangCarryStamina:OnRemoveFromEntity()
  self:CancelTask()
  self.inst:RemoveEventCallback("equip", self._onstatechanged)
  self.inst:RemoveEventCallback("unequip", self._onstatechanged)
  self.inst:RemoveEventCallback("mounted", self._onstatechanged)
  self.inst:RemoveEventCallback("dismounted", self._onstatechanged)
  self.inst.components.inventory.noheavylifting = false
end

return WangCarryStamina
