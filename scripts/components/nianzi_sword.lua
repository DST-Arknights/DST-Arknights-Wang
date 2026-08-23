-- 拈子剑标记组件
-- 仅用于在实体上挂载 POINT 动作采集器（modmain/nianzi_sword.lua 的 AddComponentAction）
-- 挂在 SetPristine 之前，客户端也有该组件实例 → 装备剑右键点击地面可生成落子动作
local NianziSword = Class(function(self, inst)
  self.inst = inst
end)

return NianziSword
