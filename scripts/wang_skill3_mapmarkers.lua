-- 天下劫地图选点聚合管理。
--
-- 已部署棋子按固定世界网格聚合：每个聚合格只保留一个长期存在的地图代理。
-- 代理随棋子部署/移除维护，而不是玩家打开三技能时临时创建，避免地图上反复刷点。
-- 聚合格固定锚定世界坐标，读档/增减棋子时同一格的选点不会漂移。

local MapMarkers = {
  clusters = {},
}

local MAP_MARKER_TAG = "wang_skill3_map_marker"

local function GetClusterSize()
  return math.max(2, (TUNING.WANG and TUNING.WANG.SKILL3_MAP_CLUSTER_SIZE) or 20)
end

local function GetClusterCoord(x, z)
  local size = GetClusterSize()
  return math.floor(x / size), math.floor(z / size), size
end

local function GetClusterKey(gx, gz)
  return tostring(gx) .. ":" .. tostring(gz)
end

local function CreateMarker(gx, gz, size)
  local marker = SpawnPrefab("wang_skill3_map_marker")
  if marker == nil then
    return nil
  end

  marker:AddTag(MAP_MARKER_TAG)
  marker.Transform:SetPosition((gx + 0.5) * size, 0, (gz + 0.5) * size)
  return marker
end

function MapMarkers:Register(piece)
  if not TheWorld.ismastersim or piece == nil or not piece:IsValid() then
    return
  end

  -- 部署逻辑理论上只注册一次；这里保留幂等，避免异常路径重复计数。
  if piece._wang_skill3_map_cluster_key ~= nil then
    return
  end

  local x, _, z = piece.Transform:GetWorldPosition()
  local gx, gz, size = GetClusterCoord(x, z)
  local key = GetClusterKey(gx, gz)
  local cluster = self.clusters[key]

  if cluster == nil then
    cluster = {
      count = 0,
      pieces = {},
      marker = CreateMarker(gx, gz, size),
    }
    self.clusters[key] = cluster
  elseif cluster.marker == nil or not cluster.marker:IsValid() then
    -- 地图代理若被其它逻辑意外移除，下一次该格注册棋子时自动补回。
    cluster.marker = CreateMarker(gx, gz, size)
  end

  cluster.pieces[piece] = true
  cluster.count = cluster.count + 1
  piece._wang_skill3_map_cluster_key = key
end

function MapMarkers:FindNearestMarker(x, z, range)
  local maxdsq = (range or 5) ^ 2
  local closest, closestdsq
  for _, cluster in pairs(self.clusters) do
    local marker = cluster.marker
    if marker ~= nil and marker:IsValid() then
      local mx, _, mz = marker.Transform:GetWorldPosition()
      local dx, dz = mx - x, mz - z
      local dsq = dx * dx + dz * dz
      if dsq <= maxdsq and (closestdsq == nil or dsq < closestdsq) then
        closest, closestdsq = marker, dsq
      end
    end
  end
  return closest
end

function MapMarkers:Unregister(piece)
  if not TheWorld.ismastersim or piece == nil then
    return
  end

  local key = piece._wang_skill3_map_cluster_key
  if key == nil then
    return
  end
  piece._wang_skill3_map_cluster_key = nil

  local cluster = self.clusters[key]
  if cluster == nil or cluster.pieces[piece] == nil then
    return
  end

  cluster.pieces[piece] = nil
  cluster.count = cluster.count - 1
  if cluster.count <= 0 then
    if cluster.marker ~= nil and cluster.marker:IsValid() then
      cluster.marker:Remove()
    end
    self.clusters[key] = nil
  end
end

return MapMarkers
