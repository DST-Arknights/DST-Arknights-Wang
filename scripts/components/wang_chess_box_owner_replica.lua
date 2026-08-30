local WangChessBoxOwnerReplica = Class(function(self, inst)
  self.inst = inst
  self._box_has_piece = net_bool(inst.GUID,
    "wang_chess_box_owner.box_has_piece", "wang_chess_box_owner_boxpiecesdirty")
end)

function WangChessBoxOwnerReplica:BoxHasPiece()
  return self._box_has_piece:value()
end

function WangChessBoxOwnerReplica:SetBoxHasPiece(haspiece)
  self._box_has_piece:set(haspiece == true)
end

return WangChessBoxOwnerReplica
