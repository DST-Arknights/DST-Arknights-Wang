-- ════════════════════════════════════════════════════════
-- 望棋子网格缓存（主机 / 客机各自维护）
-- 对外 API 一律使用网格坐标 (gx, gz)；CellKey 仅是内部 table 索引实现。
-- 棋子先确定 Transform，再通过联网占格状态声明自己占格；主客机收到状态后登记同一枚实体。
-- 动作采集器只查本地 cells，不做空间扫描。
-- 棋子移除后的邻子加成残留独立记录，不属于占格。
-- ════════════════════════════════════════════════════════

local GRID_SIZE = (TUNING.WANG and TUNING.WANG.PIECE_GRID_SIZE) or 2
local NEIGHBOR_LINGER = TUNING.WANG.PIECE_NEIGHBOR_LINGER
local NEIGHBOR_OFFSETS = {
  cross = {
    { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
  },
  square = {
    { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
    { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
  },
}

local Grid = {
  cells = {},        -- key -> 当前占格的 piece 实体
  pieceCells = {},   -- piece -> key，释放时不依赖实体当前位置
  removedUntil = {}, -- key -> 已部署棋子移除后的邻子加成截止时间
}

local function CellKey(gx, gz)
  return gx * 1048576 + gz
end

local function GetValidPiece(self, key)
  local piece = self.cells[key]
  if piece ~= nil and not piece:IsValid() then
    self.cells[key] = nil
    self.pieceCells[piece] = nil
    piece = nil
  end
  return piece
end

local function HasRemovedNeighbor(self, key, now)
  local expires = self.removedUntil[key]
  if expires == nil then
    return false
  end
  if now >= expires then
    self.removedUntil[key] = nil
    return false
  end
  return true
end

-- 世界坐标 -> 网格坐标。
function Grid:WorldToCell(x, z)
  return math.floor(x / GRID_SIZE), math.floor(z / GRID_SIZE)
end

-- 网格坐标 -> 格中心世界坐标。
function Grid:CellCenter(gx, gz)
  return (gx + 0.5) * GRID_SIZE, (gz + 0.5) * GRID_SIZE
end

-- 世界坐标吸附；仅此接口同时接收/返回世界坐标。
function Grid:SnapWorldPos(x, z)
  if not (TUNING.WANG and TUNING.WANG.PIECE_GRID_SNAP) then
    return x, z
  end
  local gx, gz = self:WorldToCell(x, z)
  return self:CellCenter(gx, gz)
end

function Grid:GetPiece(gx, gz)
  return GetValidPiece(self, CellKey(gx, gz))
end

function Grid:IsOccupied(gx, gz)
  return self:GetPiece(gx, gz) ~= nil
end

function Grid:CountNeighbors(gx, gz, neighborMode)
  local now = GetTime()
  local count = 0
  for _, offset in ipairs(NEIGHBOR_OFFSETS[neighborMode or "cross"]) do
    local key = CellKey(gx + offset[1], gz + offset[2])
    if GetValidPiece(self, key) ~= nil or HasRemovedNeighbor(self, key, now) then
      count = count + 1
    end
  end
  return count
end

-- 登记真实棋子实体；同一实体重复登记幂等，目标格已有其它实体则失败。
function Grid:Register(piece, gx, gz)
  if piece == nil or not piece:IsValid() then
    return false
  end

  local key = CellKey(gx, gz)
  local current = GetValidPiece(self, key)
  if current ~= nil and current ~= piece then
    return false
  end

  local oldKey = self.pieceCells[piece]
  if oldKey ~= nil and oldKey ~= key and self.cells[oldKey] == piece then
    self.cells[oldKey] = nil
  end

  self.cells[key] = piece
  self.pieceCells[piece] = key
  self.removedUntil[key] = nil
  return true
end

-- 通过反向表释放，不读取棋子当前位置；只有服务端已部署棋子移除时传 linger=true。
function Grid:Unregister(piece, linger)
  local key = self.pieceCells[piece]
  if key == nil then
    return false
  end

  if self.cells[key] == piece then
    self.cells[key] = nil
  end
  self.pieceCells[piece] = nil

  if linger then
    self.removedUntil[key] = GetTime() + NEIGHBOR_LINGER
  end
  return true
end

return Grid
