-- ════════════════════════════════════════════════════════
-- 棋盒主人组件（挂在玩家上，主世界专用）
-- 宠物式存在：棋盒全程 persists=false（inv/世界档都不存），存档数据由主人全权管理
--   主人下线(player_despawn) → 捕获棋盒 GetSaveRecord（含容器内容）+ 所在模式 → 移除棋盒
--   主人上线/读档 → 从记录 SpawnSaveRecord 重生，按模式放回背包或放身边跟随
-- 因为棋盒 persists=false，inv:OnSave 跳过它（inventory.lua `if v.persists`），
-- 读档时 inv 不会重复触发进包事件，存档唯一来源是本组件
-- ════════════════════════════════════════════════════════
-- 主人下线：捕获棋盒记录并移除（player_despawn 先于 SerializeUserSession 触发）
-- 保留 _box_mode 供 OnSave 持久化（决定上线后放回背包还是放身边）
local function OnPlayerDespawned(self)
  local box = self._box
  if box ~= nil and box:IsValid() then
    if box.components.container ~= nil then
      box.components.container:Close()
    end
    self._box_record = box:GetSaveRecord()
    box:Remove()
  end
  self._box = nil
end

local WangChessBoxOwner = Class(function(self, inst)
  self.inst = inst
  self._box = nil        -- 当前棋盒实体（无论背包态或跟随态）
  self._box_mode = nil   -- "inventory"（在背包） / "following"（跟随）
  self._box_record = nil -- 棋盒存档记录

  inst:ListenForEvent("player_despawn", function()
    OnPlayerDespawned(self)
  end)
end)

function WangChessBoxOwner:GetBox()
  return self._box
end

-- 登记棋盒（进出背包/放下跟随时由棋盒调用）；清除任何过期记录
function WangChessBoxOwner:TrackBox(box, mode)
  self._box = box
  self._box_mode = mode
  self._box_record = nil
end

-- 清除登记（棋盒被其他玩家接管/移除时）
function WangChessBoxOwner:ClearBox()
  self._box = nil
  self._box_mode = nil
  self._box_record = nil
end

-- 主人上线：从记录重生棋盒，按模式放回背包或放身边跟随
function WangChessBoxOwner:SpawnBox()
  if self._box_record == nil then
    return
  end
  local record = self._box_record
  local mode = self._box_mode
  self._box_record = nil
  self._box_mode = nil

  local box = SpawnSaveRecord(record)
  if box ~= nil then
    self._box = box
    box.persists = false

    -- 背包态：GiveItem 回主人背包（触发 OnPutInInventory，会 TrackBox + 关闭容器）
    if mode == "inventory" and self.inst.components.inventory ~= nil
        and self.inst.components.inventory:GiveItem(box) then
      return
    end

    -- 跟随态（或进背包失败兜底）：放身边跟随
    self._box_mode = "following"
    if box.components.inventoryitem ~= nil then
      box.components.inventoryitem.canbepickedup = true
    end
    local x, y, z = self.inst.Transform:GetWorldPosition()
    box.Transform:SetPosition(x, y, z)
    if box.components.follower ~= nil then
      box.components.follower:SetLeader(self.inst)
    end
    if box.sg ~= nil then
      box.sg:GoToState("idle")
    end
  end
end

function WangChessBoxOwner:OnSave()
  -- 直接捕获当前棋盒记录（无论背包/跟随态）
  if self._box ~= nil and self._box:IsValid() then
    self._box_record = self._box:GetSaveRecord()
  end
  if self._box_record ~= nil then
    return { box_record = self._box_record, box_mode = self._box_mode }
  end
end

function WangChessBoxOwner:OnLoad(data)
  if data ~= nil and data.box_record ~= nil then
    self._box_record = data.box_record
    self._box_mode = data.box_mode
    -- 延迟一帧重生，确保玩家与背包已就位（inv 读档不会触发进包事件，无重复）
    self.inst:DoTaskInTime(0, function()
      if self.inst:IsValid() then
        self:SpawnBox()
      end
    end)
  end
end

return WangChessBoxOwner
