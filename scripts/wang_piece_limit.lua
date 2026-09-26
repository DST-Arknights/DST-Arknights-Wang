local PieceLimit = {
  piecesByOwner = {},
  nextOrder = 0,
}

local function IsOlder(a, b)
  if a._deployTime ~= b._deployTime then
    return a._deployTime < b._deployTime
  end
  return a._deployOrder < b._deployOrder
end

function PieceLimit:GetLimit(deployer)
  local elite = deployer.components.ark_elite
  if elite == nil then
    return TUNING.WANG.PIECE_DEFAULT_LIMIT
  end

  local baseHealth = TUNING.WANG_HEALTH
  local eliteHealth = baseHealth + elite:GetHealthBonus()
  return math.clamp(baseHealth - eliteHealth, 1, baseHealth - 1)
end

function PieceLimit:Register(piece, deployer)
  piece._deployTime = piece._deployTime or GetTime()
  if piece._deployOrder == nil then
    self.nextOrder = self.nextOrder + 1
    piece._deployOrder = self.nextOrder
  else
    self.nextOrder = math.max(self.nextOrder, piece._deployOrder)
  end
  if deployer ~= nil then
    piece._deployerUserid = deployer.userid
  end

  local userid = piece._deployerUserid
  if userid == nil then
    return
  end
  local pieces = self.piecesByOwner[userid]
  if pieces == nil then
    pieces = {}
    self.piecesByOwner[userid] = pieces
  end
  table.insert(pieces, piece)

  -- Loading only rebuilds the index; the next deployment checks the owner's current limit.
  if deployer ~= nil then
    local limit = self:GetLimit(deployer)
    if #pieces > limit then
      table.sort(pieces, IsOlder)
      while #pieces > limit do
        local oldest = pieces[1]
        SpawnPrefab("cavehole_flick").Transform:SetPosition(oldest.Transform:GetWorldPosition())
        oldest:Remove()
      end
    end
  end
end

function PieceLimit:Unregister(piece)
  local userid = piece._deployerUserid
  local pieces = self.piecesByOwner[userid]
  if pieces == nil then
    return
  end

  for index, owned in ipairs(pieces) do
    if owned == piece then
      table.remove(pieces, index)
      break
    end
  end
  if #pieces == 0 then
    self.piecesByOwner[userid] = nil
  end
end

return PieceLimit
