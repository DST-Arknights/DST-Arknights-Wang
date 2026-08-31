local WangPieceResource = {}

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
