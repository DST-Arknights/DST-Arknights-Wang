local fxs = { {
  name = "wang_piece_explode_smoke_fx",
  bank = "die_fx",
  build = "die",
  anim = "small",
  scale_with_parent_size = true,
}, {
  name = "wang_piece_explode_shadow_fx",
  bank = "pocketwatch_weapon_fx",
  build = "pocketwatch_weapon_fx",
  anim = function() return "idle_big_" .. math.random(3) end,
  sound = "wanda2/characters/wanda/watch/weapon/shadow_hit_old",
  scale_with_parent_size = true,
  fn = function(inst)
    inst.AnimState:SetFinalOffset(1)
  end,
} }

local prefabs = {
  ArkMakePing("reticuleaoeping_6", "ping_target_6", true, 1.1),
}
for _, fx in ipairs(fxs) do
  table.insert(prefabs, ArkMakeFx(fx))
end

return unpack(prefabs)
