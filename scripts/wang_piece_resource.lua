local WangPieceResource = {}

local function IsExternalPieceBox(doer, box)
  return box ~= nil
    and box:IsValid()
    and box.components.follower:GetLeader() == doer
    and not box.components.inventoryitem:IsHeld()
end

-- 按铸子规则投放：外挂跟随棋盒 → 物品栏/装备栏棋盒 → 普通物品栏。
function WangPieceResource.Give(doer, item)
  local inventory = doer.components.inventory
  local owner = doer.components.wang_chess_box_owner
  local boundbox = owner ~= nil and owner:GetBox() or nil
  if IsExternalPieceBox(doer, boundbox)
      and boundbox.components.container:GiveItem(item, nil, nil, false) == true then
    return true
  end

  local boxes = inventory:FindItems(function(candidate)
    return candidate.prefab == "piece_box"
  end)
  for _, box in ipairs(boxes) do
    if box.components.container:GiveItem(item, nil, nil, false) == true then
      return true
    end
  end

  return inventory:GiveItem(item) == true
end

function WangPieceResource.Has(doer, amount)
  if doer == nil then
    return false
  end
  amount = math.max(1, math.floor(amount or 1))

  local owner = doer.components ~= nil and doer.components.wang_chess_box_owner or nil
  if owner ~= nil then
    return owner:HasPieces(amount)
  end

  local inventory = doer.replica ~= nil and doer.replica.inventory or nil
  if inventory ~= nil and inventory:Has("piece", amount) then
    return true
  end
  local owner_replica = doer.replica ~= nil and doer.replica.wang_chess_box_owner or nil
  return amount == 1 and owner_replica ~= nil and owner_replica:BoxHasPiece()
end

function WangPieceResource.HasAny(doer)
  return WangPieceResource.Has(doer, 1)
end

function WangPieceResource.TryConsume(doer, amount)
  if doer == nil then
    return false
  end
  local owner = doer.components ~= nil and doer.components.wang_chess_box_owner or nil
  if owner ~= nil then
    return owner:TryConsumePieces(amount)
  end

  local inventory = doer.components ~= nil and doer.components.inventory or nil
  amount = amount or 1
  if inventory == nil or not inventory:Has("piece", amount) then
    return false
  end
  inventory:ConsumeByName("piece", amount)
  return true
end

return WangPieceResource
