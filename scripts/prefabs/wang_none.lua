local assets =
{
	Asset( "ANIM", "anim/wang.zip" ),
	Asset( "ANIM", "anim/ghost_wang_build.zip" ),
}

local skins =
{
	normal_skin = "wang",
	ghost_skin = "ghost_wang_build",
}

local base_prefab = "wang"

local tags = {"BASE", "WANG", "CHARACTER"}

return CreatePrefabSkin("wang_none",
{
	base_prefab = base_prefab,
	skins = skins,
	assets = assets,
	skin_tags = tags,

	build_name_override = "wang",
	rarity = "Character",
})
