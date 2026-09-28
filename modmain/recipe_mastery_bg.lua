local MASTERY_ATLAS = "images/recipe_mastery_bg.xml"
local MASTERY_TEXTURES = {
  [RECIPE_MASTERY_STATE.MASTERING] = "mastering.tex",
  [RECIPE_MASTERY_STATE.MASTERED] = "mastered.tex",
}

AddClassPostConstruct("widgets/redux/craftingmenu_widget", function(self)
  ArkHookFunction(self.recipe_grid, "update_fn", function(next, context, widget, data, index)
    next(context, widget, data, index)

    if data == nil or data.recipe == nil then
      return
    end

    local mastery = self.owner.replica.recipe_mastery
    local texture = mastery ~= nil and MASTERY_TEXTURES[mastery:GetState(data.recipe.name)] or nil
    if texture ~= nil then
      local width, height = widget.bg:GetSize()
      widget.bg:SetTexture(MASTERY_ATLAS, texture)
      widget.bg:SetSize(width, height)
    end
  end)

  self.inst:ListenForEvent("recipe_mastery_recipesdirty", function()
    if self._recipe_mastery_bg_refresh_pending then
      return
    end
    self._recipe_mastery_bg_refresh_pending = true
    self.inst:DoTaskInTime(0, function()
      self._recipe_mastery_bg_refresh_pending = nil
      self.recipe_grid:RefreshView()
    end)
  end, self.owner)
end)
