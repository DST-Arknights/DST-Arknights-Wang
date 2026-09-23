-- 望的主动语音表；随机 talk_LP 由客户端的 talksoundoverride 直接播放。
local function Voice(event, zh_duration, jp_duration, hunan_duration)
  return {
    zh = {
      path = "wang/voice_zh/" .. event,
      duration = zh_duration,
    },
    jp = {
      path = "wang/voice_jp/" .. event,
      duration = jp_duration,
    },
    hunan = {
      path = "wang/voice_hunan/" .. event,
      duration = hunan_duration,
    },
  }
end

return {
  WANG_SKILL1_CAST = Voice("skill1_cast", 3.0, 3.4, 3.4),
  WANG_SKILL2_CAST = Voice("skill2_cast", 3.0, 3.4, 3.4),
  WANG_SKILL3_CAST = Voice("skill3_cast", 3.2, 3.4, 3.2),
}
