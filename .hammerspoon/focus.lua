--[[

focus.lua

Set application bindings here!

]]--

hs.hotkey.bind(hyper, "C", function ()
  hs.application.launchOrFocus('Google Chrome')
end)

hs.hotkey.bind(hyper,  "V", function()
  hs.application.launchOrFocus('Visual Studio Code')
end)

hs.hotkey.bind(hyper,  "W", function()
  hs.application.launchOrFocus('Microsoft Word')
end)

hs.hotkey.bind(hyper,  "S", function()
  hs.application.launchOrFocus('Spotify')
end)

hs.hotkey.bind(hyper,  "M", function()
  hs.application.launchOrFocus('Messages')
end)

hs.hotkey.bind(hyper, "N", function()
  hs.application.launchOrFocus('Notion')
end)

hs.hotkey.bind(hyper, "Z", function()
  hs.application.launchOrFocus('Screenshot')
end)

hs.hotkey.bind(hyper,  "space", function()
  hs.application.launchOrFocus('iTerm')
end)

hs.hotkey.bind(hyper,  "Q", function()
  hs.application.launchOrFocus('Quip')
end)

hs.hotkey.bind(hyper, "1", function()
  hs.execute("open ~/")
end)

hs.hotkey.bind(hyper, "2", function()
  hs.execute("open ~/Documents")
end)

hs.hotkey.bind(hyper, "3", function()
  hs.execute("open ~/Dropbox/projects")
end)

