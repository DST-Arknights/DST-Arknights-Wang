-- 望的音效与主动语音共用入口。
-- 技能音效由服务端权威触发；随机语音的 talk_LP 由 wang.lua 的客户端副本绑定。
local Audio = {}

local SFX_ROOT = "wang/sfx/"

local function PlaySfx(inst, event, volume)
  if inst ~= nil and inst.SoundEmitter ~= nil then
    inst.SoundEmitter:PlaySound(SFX_ROOT .. event, nil, volume)
  end
end

-- 原版 stone_drop 是地面碎石/棋类落地特效使用的短促接触声；
-- 与 Wang 的两种黑子部署素材叠加，保留原版部署质感。
function Audio.PlayPiecePlace(inst)
  if inst ~= nil and inst.SoundEmitter ~= nil then
    inst.SoundEmitter:PlaySound("dontstarve/common/stone_drop", nil, 0.55)
  end
  PlaySfx(inst, "piece_place", 0.45)
end

function Audio.PlaySfx(inst, event, volume)
  PlaySfx(inst, event, volume)
end

-- 同一角色的技能台词共享冷却，避免连续触发时语音互相截断。
function Audio.TrySayVoice(inst, key, opts)
  if inst == nil or key == nil or SayAndVoice == nil then
    return false
  end
  local now = GetTime()
  if now < (inst._wang_next_voice_time or 0) then
    return false
  end
  inst._wang_next_voice_time = now + (TUNING.WANG.VOICE_CD or 2)

  opts = opts or {}
  opts.voice_channel = opts.voice_channel or "wang_skill_voice"
  SayAndVoice(inst, key, opts)
  return true
end

return Audio
