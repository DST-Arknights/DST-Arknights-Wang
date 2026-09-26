-- ════════════════════════════════════════════════════════
-- 望棋子网格占用表（共享模块，主世界维护状态，客户端可查）
-- 整图按 TUNING.WANG.PIECE_GRID_SIZE（网格边长，默认 2）切成格子，
-- 每格至多一枚已部署棋子；占用位置在格内自由偏移（吸附开关控制是否居中）。
-- 投掷和延迟落子共用 TryOccupy → SetPiece → Release；SetPiece 可直接登记空格。
-- 正常流程按坐标完成设置或释放；TheWorld 超时只兜底未设置棋子的空占位。
-- 棋子移除后只记录时间，过期历史在下次访问时清理，不安排额外任务。
-- 读档由棋子重新登记；历史残留不占格，也不计入玩家部署数量。
-- ════════════════════════════════════════════════════════

local GRID_SIZE = (TUNING.WANG and TUNING.WANG.PIECE_GRID_SIZE) or 2
local OCCUPANCY_TIMEOUT = (TUNING.WANG and TUNING.WANG.PIECE_PLACEHOLDER_TIMEOUT) or 3
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
  cells = {}, -- key → { occupied, piece, task, removedAt }
}

-- 格号（世界锚定：坐标/边长 向下取整；支持负坐标）
local function CellCoord(x, z)
  return math.floor(x / GRID_SIZE), math.floor(z / GRID_SIZE)
end

local function CellKey(gx, gz)
  return gx * 1048576 + gz
end

local function GetCell(self, key, now)
  local cell = self.cells[key]
  if cell ~= nil and not cell.occupied
      and cell.removedAt ~= nil and now - cell.removedAt >= NEIGHBOR_LINGER then
    self.cells[key] = nil
    return nil
  end
  return cell
end

-- 世界坐标 → 格号
function Grid:CellCoord(x, z)
  return CellCoord(x, z)
end

-- 格中心世界坐标（吸附用）
function Grid:CellCenterAt(x, z)
  local gx, gz = CellCoord(x, z)
  return (gx + 0.5) * GRID_SIZE, (gz + 0.5) * GRID_SIZE
end

-- 部署位置：吸附开关 ON → 格中心；OFF → 原样（自由偏移）
function Grid:SnapPos(x, z)
  if TUNING.WANG and TUNING.WANG.PIECE_GRID_SNAP then
    return Grid:CellCenterAt(x, z)
  end
  return x, z
end

-- 目标格是否被占用（已设置棋子或空占位）
function Grid:IsCellTaken(x, z)
  local cell = GetCell(self, CellKey(CellCoord(x, z)), GetTime())
  return cell ~= nil and cell.occupied == true
end

-- 取得目标格中的棋子；空占位不算已有棋子。
function Grid:GetPieceAt(x, z)
  local entry = GetCell(self, CellKey(CellCoord(x, z)), GetTime())
  local piece = entry ~= nil and entry.piece or nil
  return piece ~= nil and piece:IsValid() and piece or nil
end

function Grid:CountNeighbors(x, z, neighborMode)
  local gx, gz = CellCoord(x, z)
  local now = GetTime()
  local count = 0
  for _, offset in ipairs(NEIGHBOR_OFFSETS[neighborMode or "cross"]) do
    local key = CellKey(gx + offset[1], gz + offset[2])
    local entry = GetCell(self, key, now)
    local piece = entry ~= nil and entry.piece or nil
    local removedAt = entry ~= nil and entry.removedAt or nil
    if (piece ~= nil and piece:IsValid()) or (removedAt ~= nil and now - removedAt < NEIGHBOR_LINGER) then
      count = count + 1
    end
  end
  return count
end

-- 动作采集器用的占用判断：主世界含占位（权威）；客户端空间查询近似（仅已落地棋子）
-- 客户端看不到占位（占位是服务端状态），权威拦截在动作执行处
function Grid:IsCellTakenForAction(x, z)
  if TheWorld.ismastersim then
    return self:IsCellTaken(x, z)
  end
  local ents = TheSim:FindEntities(x, 0, z, 2 * GRID_SIZE, { "wang_piece_deployed" }, nil)
  for _, p in ipairs(ents) do
    local px, _, pz = p.Transform:GetWorldPosition()
    if CellKey(CellCoord(px, pz)) == CellKey(CellCoord(x, z)) then
      return true
    end
  end
  return false
end

-- 先占格，不依赖棋子实体；设置棋子后自动取消超时任务。
function Grid:TryOccupy(x, z)
  local key = CellKey(CellCoord(x, z))
  local cell = GetCell(self, key, GetTime())
  if cell ~= nil and cell.occupied then
    return false
  end

  cell = cell or {}
  self.cells[key] = cell
  cell.occupied = true
  cell.task = TheWorld:DoTaskInTime(OCCUPANCY_TIMEOUT, function()
    if cell.occupied and cell.piece == nil then
      self:Release(x, z)
    end
  end)
  return true
end

-- 填入已占位格子，也可直接登记空格；调用方负责前置占位检查。
function Grid:SetPiece(x, z, piece)
  local key = CellKey(CellCoord(x, z))
  local cell = GetCell(self, key, GetTime())
  if cell ~= nil and cell.piece ~= nil and cell.piece ~= piece then
    return false
  end

  cell = cell or {}
  self.cells[key] = cell
  if cell.task ~= nil then
    cell.task:Cancel()
    cell.task = nil
  end
  cell.occupied = true
  cell.piece = piece
  return true
end

function Grid:Release(x, z)
  local key = CellKey(CellCoord(x, z))
  local cell = self.cells[key]
  if cell == nil or not cell.occupied then
    return false
  end
  if cell.task ~= nil then
    cell.task:Cancel()
    cell.task = nil
  end
  if cell.piece ~= nil then
    cell.removedAt = GetTime()
  end
  cell.piece = nil
  cell.occupied = false
  if cell.removedAt == nil then
    self.cells[key] = nil
  end
  return true
end

return Grid
