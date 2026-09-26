-- ════════════════════════════════════════════════════════
-- 望棋子网格占用表（共享模块，主世界维护状态，客户端可查）
-- 整图按 TUNING.WANG.PIECE_GRID_SIZE（网格边长，默认 2）切成格子，
-- 每格至多一枚已部署棋子；占用位置在格内自由偏移（吸附开关控制是否居中）。
-- 投掷飞行期间对目标格打"占位"（ReserveCell），超时自动解锁，避免连续投掷堆叠。
-- 占用数据挂在已部署棋子自身（SetDeployedState 注册 / onremove 释放），
-- 读档恢复自动重新注册，无存档、无全图扫描。
-- 网格同时供爆炸查询邻子加成；棋子移除后的短期残留不占格。
-- ════════════════════════════════════════════════════════

local GRID_SIZE = (TUNING.WANG and TUNING.WANG.PIECE_GRID_SIZE) or 2
local PLACEHOLDER_TIMEOUT = (TUNING.WANG and TUNING.WANG.PIECE_PLACEHOLDER_TIMEOUT) or 3
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
  cells = {}, -- key = gx*1048576+gz → { piece=已部署棋子 } 或 { reservation=飞行棋子, task=超时任务 }
  removedUntil = {}, -- 已部署棋子移除后的加成截止时间，不影响占位。
}

-- 格号（世界锚定：坐标/边长 向下取整；支持负坐标）
local function CellCoord(x, z)
  return math.floor(x / GRID_SIZE), math.floor(z / GRID_SIZE)
end

local function CellKey(gx, gz)
  return gx * 1048576 + gz
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

-- 目标格是否被占用（已部署棋子 或 投掷占位）
function Grid:IsCellTaken(x, z)
  return self.cells[CellKey(CellCoord(x, z))] ~= nil
end

-- 取得目标格中的已部署棋子；投掷占位不算已有棋子。
function Grid:GetPieceAt(x, z)
  local entry = self.cells[CellKey(CellCoord(x, z))]
  local piece = entry ~= nil and entry.piece or nil
  return piece ~= nil and piece:IsValid() and piece or nil
end

function Grid:CountNeighbors(x, z, neighborMode)
  local gx, gz = CellCoord(x, z)
  local now = GetTime()
  local count = 0
  for _, offset in ipairs(NEIGHBOR_OFFSETS[neighborMode or "cross"]) do
    local key = CellKey(gx + offset[1], gz + offset[2])
    local entry = self.cells[key]
    local piece = entry ~= nil and entry.piece or nil
    local expires = self.removedUntil[key]
    if (piece ~= nil and piece:IsValid()) or (expires ~= nil and now < expires) then
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

-- 部署占用：格子空闲才成功（调用方已查 IsCellTaken，此处兜底）
function Grid:TryOccupy(x, z, piece)
  local key = CellKey(CellCoord(x, z))
  local current = self.cells[key]
  if current ~= nil and current.reservation == piece then
    if current.task ~= nil then
      current.task:Cancel()
      current.task = nil
    end
    current.reservation = nil
    current.piece = piece
    piece._wang_gridKey = key
    return true
  end
  if current ~= nil then
    return false
  end
  self.cells[key] = { piece = piece }
  piece._wang_gridKey = key
  return true
end

-- 投掷起飞占位：目标格空闲才打占位，超时自动解锁（落地/移除会提前 Detach）
function Grid:ReserveCell(piece, x, z)
  local key = CellKey(CellCoord(x, z))
  if self.cells[key] ~= nil then
    return false
  end
  self.cells[key] = {
    reservation = piece,
    task = piece:DoTaskInTime(PLACEHOLDER_TIMEOUT, function()
      -- 仅在仍持有该占位时才解锁（落地占用/二次占位后不误删）
      if piece._wang_gridKey == key then
        Grid:Detach(piece)
      end
    end),
  }
  piece._wang_gridKey = key
  return true
end

-- 解除棋子的一切登记（占位 或 已部署）：落地清占位 / 棋子移除时调用
function Grid:Detach(piece)
  local key = piece._wang_gridKey
  if key == nil then
    return
  end
  piece._wang_gridKey = nil
  local e = self.cells[key]
  if e ~= nil and (e.piece == piece or e.reservation == piece) then
    if e.piece == piece then
      local expires = GetTime() + NEIGHBOR_LINGER
      self.removedUntil[key] = expires
      -- 挂在世界上，避免随棋子移除被取消；同格再次移除会延长残留。
      TheWorld:DoTaskInTime(NEIGHBOR_LINGER, function()
        if self.removedUntil[key] == expires then
          self.removedUntil[key] = nil
        end
      end)
    end
    if e.task ~= nil then
      e.task:Cancel()
      e.task = nil
    end
    self.cells[key] = nil
  end
end

return Grid
