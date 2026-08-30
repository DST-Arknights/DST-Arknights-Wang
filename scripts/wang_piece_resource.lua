local WangPieceResource = {}

function WangPieceResource.HasAny(doer)
  if doer == nil then
    return false
  end

  local owner = doer.components ~= nil and doer.components.wang_chess_box_owner or nil
  if owner ~= nil then
    return owner:HasPieces(1)
  end

  local inventory = doer.replica ~= nil and doer.replica.inventory or nil
  if inventory ~= nil and inventory:Has("piece", 1) then
    return true
  end
  local owner_replica = doer.replica ~= nil and doer.replica.wang_chess_box_owner or nil
  return owner_replica ~= nil and owner_replica:BoxHasPiece()
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
