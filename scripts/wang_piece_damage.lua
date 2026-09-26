local function GetEliteBonusDamage(deployer)
  local elite = deployer ~= nil and deployer.components.ark_elite or nil
  return elite ~= nil
      and TUNING.WANG.PIECE_ELITE_DAMAGE_PER_LEVEL * elite:_GetCumulativeLevel() or 0
end

return GetEliteBonusDamage
