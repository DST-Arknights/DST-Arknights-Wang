-- ════════════════════════════════════════════════════════
-- 棋盒主人组件（挂在玩家上，主世界专用）
-- 每名玩家只能绑定一个棋盒；绑定中的棋盒由本组件嵌入主人存档。
-- 被换下的棋盒解除绑定并恢复世界持久化，留在地面等待其他玩家拾取。

local PIECE_PREFAB = "piece"

local function SetReplicaHasPiece(self, haspiece)
  local replica = self.inst.replica ~= nil and self.inst.replica.wang_chess_box_owner or nil
  if replica ~= nil then
    replica:SetBoxHasPiece(haspiece)
  end
end

local function DetachBoxListeners(self, box)
  if box ~= nil then
    box:RemoveEventCallback("itemget", self._onboxcontentschanged)
    box:RemoveEventCallback("itemlose", self._onboxcontentschanged)
    box:RemoveEventCallback("onremove", self._onboxremoved)
  end
end

local function AttachBoxListeners(self, box)
  box:ListenForEvent("itemget", self._onboxcontentschanged)
  box:ListenForEvent("itemlose", self._onboxcontentschanged)
  box:ListenForEvent("onremove", self._onboxremoved)
end

local function OnPlayerDespawned(self)
  local box = self._box
  if box ~= nil and box:IsValid() then
    if box.components.container ~= nil then
      box.components.container:Close()
    end
    self._box_record = box:GetSaveRecord()
    DetachBoxListeners(self, box)
    self._box = nil
    SetReplicaHasPiece(self, false)
    box:Remove()
  end
  self._box = nil
  SetReplicaHasPiece(self, false)
end

local WangChessBoxOwner = Class(function(self, inst)
  self.inst = inst
  self._box = nil        -- 当前棋盒实体（无论背包态或跟随态）
  self._box_mode = nil   -- "inventory"（在背包） / "following"（跟随）
  self._box_record = nil -- 棋盒存档记录

  self._onboxcontentschanged = function(box)
    if box == self._box then
      self:RefreshBoxHasPiece()
    end
  end
  self._onboxremoved = function(box)
    if box == self._box then
      DetachBoxListeners(self, box)
      self._box = nil
      self._box_mode = nil
      self._box_record = nil
      SetReplicaHasPiece(self, false)
    end
  end

  inst:ListenForEvent("player_despawn", function()
    OnPlayerDespawned(self)
  end)
end)

function WangChessBoxOwner:GetBox()
  return self._box
end

function WangChessBoxOwner:GetBoxPieceCount()
  local container = self._box ~= nil and self._box:IsValid()
    and self._box.components.container or nil
  if container == nil then
    return 0
  end
  local _, count = container:Has(PIECE_PREFAB, 1)
  return count
end

function WangChessBoxOwner:RefreshBoxHasPiece()
  SetReplicaHasPiece(self, self:GetBoxPieceCount() > 0)
end

function WangChessBoxOwner:GetPieceCount()
  local count = self:GetBoxPieceCount()
  local inventory = self.inst.components.inventory
  if inventory ~= nil then
    local _, inventorycount = inventory:Has(PIECE_PREFAB, 1)
    count = count + inventorycount
  end
  return count
end

function WangChessBoxOwner:HasPieces(amount)
  amount = amount or 1
  local count = self:GetPieceCount()
  return count >= amount, count
end

-- 普通物品栏优先，棋盒补足；预检保证不足时不发生部分消费。
function WangChessBoxOwner:TryConsumePieces(amount)
  amount = math.max(0, math.floor(amount or 1))
  if amount == 0 then
    return true
  end

  local enough = self:HasPieces(amount)
  if not enough then
    return false
  end

  local inventory = self.inst.components.inventory
  if inventory ~= nil then
    local _, inventorycount = inventory:Has(PIECE_PREFAB, 1)
    local consume = math.min(amount, inventorycount)
    if consume > 0 then
      inventory:ConsumeByName(PIECE_PREFAB, consume)
      amount = amount - consume
    end
  end

  local container = self._box ~= nil and self._box:IsValid()
    and self._box.components.container or nil
  if amount > 0 and container ~= nil then
    container:ConsumeByName(PIECE_PREFAB, amount)
  end
  self:RefreshBoxHasPiece()
  return true
end

function WangChessBoxOwner:_DropBoundBox()
  local box = self._box
  if box == nil or not box:IsValid() then
    self._box = nil
    self._box_mode = nil
    self._box_record = nil
    SetReplicaHasPiece(self, false)
    return
  end

  DetachBoxListeners(self, box)
  self._box = nil
  self._box_mode = nil
  self._box_record = nil
  SetReplicaHasPiece(self, false)

  if box.components.container ~= nil then
    box.components.container:Close()
  end
  if box.UnbindOwner ~= nil then
    box:UnbindOwner()
  end

  local inventoryitem = box.components.inventoryitem
  if inventoryitem ~= nil and inventoryitem:IsHeld() then
    box = inventoryitem:RemoveFromOwner(true, true) or box
  end
  if box:IsValid() then
    box.Transform:SetPosition(self.inst.Transform:GetWorldPosition())
    if box.components.inventoryitem ~= nil then
      box.components.inventoryitem:OnDropped(true)
    end
  end
end

-- Inventory:GiveItem 在选槽前调用 OnPickup；先释放旧盒可为新盒腾出槽位。
function WangChessBoxOwner:PrepareForBoxPickup(box)
  local oldbox = self._box
  local inventoryitem = oldbox ~= nil and oldbox.components.inventoryitem or nil
  if oldbox ~= nil and oldbox ~= box and inventoryitem ~= nil and inventoryitem:IsHeld() then
    local was_equipped = oldbox.components.equippable ~= nil
      and oldbox.components.equippable:IsEquipped()
    local inventory = self.inst.components.inventory
    local overflow = inventory ~= nil and inventory:GetOverflowContainer() or nil
    local frees_slot = inventoryitem.owner == self.inst
      or (overflow ~= nil and inventoryitem.owner == overflow.inst)
    if not was_equipped and not frees_slot then
      return false
    end
    self:_DropBoundBox()
    return was_equipped
  end
  return false
end

function WangChessBoxOwner:TrackBox(box, mode)
  if box == nil or not box:IsValid() then
    return
  end
  if self._box ~= nil and self._box ~= box then
    self:_DropBoundBox()
  end

  if self._box ~= box then
    self._box = box
    AttachBoxListeners(self, box)
  end
  self._box_mode = mode
  self._box_record = nil
  box.persists = false
  self:RefreshBoxHasPiece()
end

-- box 参数用于防止旧 follower 的延迟回调误清除玩家刚绑定的新盒。
function WangChessBoxOwner:ClearBox(box)
  if box ~= nil and self._box ~= box then
    return
  end
  DetachBoxListeners(self, self._box)
  self._box = nil
  self._box_mode = nil
  self._box_record = nil
  SetReplicaHasPiece(self, false)
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
    self:TrackBox(box, mode)

    -- 背包态：GiveItem 回主人背包（触发 OnPutInInventory，会 TrackBox + 关闭容器）
    if mode == "inventory" and self.inst.components.inventory ~= nil
        and self.inst.components.inventory:GiveItem(box) then
      return
    end

    -- 跟随态（或进背包失败兜底）：放身边跟随
    if box.components.inventoryitem ~= nil then
      box.components.inventoryitem.canbepickedup = true
    end
    local x, y, z = self.inst.Transform:GetWorldPosition()
    box.Transform:SetPosition(x, y, z)
    if box.components.follower ~= nil then
      box.components.follower:SetLeader(self.inst)
    end
    self:TrackBox(box, "following")
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

function WangChessBoxOwner:OnRemoveFromEntity()
  DetachBoxListeners(self, self._box)
end

return WangChessBoxOwner
