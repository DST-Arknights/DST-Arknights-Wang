local Image = require("widgets/image")

local MASTERY_ATLAS = "images/recipe_mastery_bg.xml"
local MASTERY_TEXTURES = {
  [RECIPE_MASTERY_STATE.MASTERING] = "mastering.tex",
  [RECIPE_MASTERY_STATE.MASTERED] = "mastered.tex",
}

AddClassPostConstruct("widgets/redux/craftingmenu_widget", function(self)
  ArkHookFunction(self.recipe_grid, "update_fn", function(next, context, widget, data, index)
    next(context, widget, data, index)

    local mastery = self.owner.replica.recipe_mastery
    local texture = data ~= nil and data.recipe ~= nil and mastery ~= nil
        and MASTERY_TEXTURES[mastery:GetState(data.recipe.name)] or nil
    local overlay = widget._recipe_mastery_overlay

    if texture == nil then
      if overlay ~= nil then
        overlay:Hide()
      end
      return
    end

    if overlay == nil then
      overlay = widget.bg:AddChild(Image(MASTERY_ATLAS, texture))
      widget._recipe_mastery_overlay = overlay
    else
      overlay:SetTexture(MASTERY_ATLAS, texture)
    end

    local width, height = widget.bg:GetSize()
    overlay:SetSize(width, height)
    overlay:Show()
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
