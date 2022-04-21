------------------------------------- ComputerCraft compatibility -------------------------------------

local bootTime = math.floor( (os.epoch("utc") / 1000) +0.5)

_G.CCError = function(reason, level)
	term.setCursorPos(1, 1)
	term.setTextColor(colors.red)
	term.setBackgroundColor(colors.black)
	term.write(reason)
	local currY = 2
	local traceback = debug.traceback()
	--write it out, moving to next line at new lines
	for line in string.gmatch(traceback, "[^\n]+") do
		currY = currY + 1
		term.setCursorPos(1, currY)
		term.write(line)
	end
	os.pullEvent("key")
	os.reboot()
end
_G.ccfs = fs

local sides = {
	"top",
	"bottom",
	"left",
	"right",
	"front",
	"back"
}

local function tableToIter(tab)
	local i = 0
	return function()
		i = i + 1
		return tab[i]
	end
end

local colorTransformations = {
	[0xA5A5A5] = colors.lightGray,
	[0x1d1d1d] = colors.black,
	[0x000000] = colors.black,
	[0xe1e1e1] = colors.white,
	[0x010101] = colors.black,
	[0xfefefe]= colors.white,
	[0xffdb40] = colors.yellow,
	[0x3366cc] = colors.lightBlue,
	[0xffffff] = colors.white
}

_G.gputerm = term
gputerm.getResolution = term.getSize
gputerm.setForeground = function(color)
	term.setTextColor(colorTransformations[color] or color)
end
gputerm.setBackground = function(color)
	term.setBackgroundColor(colorTransformations[color] or color)
end
gputerm.fill = function(x, y, w, h, c)
	term.setCursorPos(x, y)
	for i = 1, h do
		term.write(string.rep(c, w))
		term.setCursorPos(x, y + i)
	end
end
gputerm.set = function(x, y, text)
	term.setCursorPos(x, y)
	term.write(text)
end

_G.unicode = string

local fsproxy = {}
fsproxy.ident = "fsproxy"

local fsproxyinternal = fs
fsproxyinternal.read = io.read
fsproxyinternal.close = io.close
fsproxyinternal.remove = fs.delete
fsproxyinternal.ident = "fsproxyinternal"
fsproxyinternal.lastModified = function(path)
	--this doesn't work, so return 0
	return 0
end

_G.component = {}
component.list = function(name)
	local sidesWithComponent = {}
	if name == "gpu" then
		--add internal monitor
		sidesWithComponent[1] = "internalmonitor"
		--look for monitors
		for i = 1, #sides do
			if peripheral.isPresent(sides[i]) and peripheral.getType(sides[i]) == "monitor" then
				table.insert(sidesWithComponent, sides[i])
			end
		end
	elseif name == "filesystem" then
		--add internal filesystem
		sidesWithComponent[1] = "internaldrive"
		--look for disks
		for i = 1, #sides do
			if peripheral.isPresent(sides[i]) and peripheral.getType(sides[i]) == "drive" then
				table.insert(sidesWithComponent, sides[i])
			end
		end
	end
	return tableToIter(sidesWithComponent)
end
component.proxy = function(side)
	if side == "internalmonitor" then
		return gputerm
	elseif side == "internaldrive" then
		return fsproxyinternal
	end
end

_G.computer = {}
computer.pushSignal = os.queueEvent
computer.uptime = function()
	return math.floor( (os.epoch("utc") / 1000) +0.5) - bootTime
end
computer.tmpAddress = function() return "internaldrive" end
computer.pullSignal = function(var1, ...)
	local signalnames = {...}
	if type(var1) == "number" then
		if var1 <= 0 then
			var1 = 0.1
		end
		os.startTimer(var1, "internalTimer"..var1)
		local donePulling = false
		local signal
		while not donePulling do
			signal = {os.pullEventRaw(...)}
			if signal[1] == "timer" and signal[2] == "internalTimer"..var1 then
				donePulling = true
			else
				return unpack(signal)
			end
		end
	elseif type(var1) == "string" then
		signalnames[#signalnames+1] = var1
		return os.pullEventRaw(unpack(signalnames))
	end
end

function checkArg(n, have, want, ...)
	--check if the argument matches the expected type or any type in ...
	local right = false
	local types = {...}
	for i = 1, #types do
		if type(have) == types[i] then
			right = true
			break
		end
	end
	if type(have) == want then
		right = true
	end
	if not right then
		error(string.format("bad argument #%d (%s expected, got %s)", n, want, type(have)), 2)
	end
end

_G.checkArg = checkArg

---------------------------------------- System initialization ----------------------------------------

-- Obtaining boot filesystem component proxy
local bootFilesystemProxy = fsproxyinternal
_G.firstMountDone = false

-- Executes file from boot HDD during OS initialization (will be overriden in filesystem library later)
--removed unneccessary dofile function

-- Initializing global package system
package = {
	paths = {
		["/Libraries/"] = true
	},
	loaded = {},
	loading = {}
}

-- Checks existense of specified path. It will be overriden after filesystem library initialization
local requireExists = bootFilesystemProxy.exists

-- Works the similar way as native Lua require() function
function require(module)
	-- For non-case-sensitive filesystems
	local lowerModule = unicode.lower(module)

	if package.loaded[lowerModule] then
		return package.loaded[lowerModule]
	elseif package.loading[lowerModule] then
		error("recursive require() call found: library \"" .. module .. "\" is trying to require another library that requires it\n" .. debug.traceback())
	else
		local errors = {}

		local function checkVariant(variant)
			if requireExists(variant) then
				return variant
			else
				table.insert(errors, "  variant \"" .. variant .. "\" not exists")
			end
		end

		local function checkVariants(path, module)
			return
				checkVariant(path .. module .. ".lua") or
				checkVariant(path .. module) or
				checkVariant(module)
		end

		local modulePath
		for path in pairs(package.paths) do
			modulePath =
				checkVariants(path, module) or
				checkVariants(path, unicode.upper(unicode.sub(module, 1, 1)) .. unicode.sub(module, 2, -1))
			
			if modulePath then
				package.loading[lowerModule] = true
				local result = dofile(modulePath)
				package.loaded[lowerModule] = result or true
				package.loading[lowerModule] = nil
				
				return result
			end
		end

		error("unable to locate library \"" .. module .. "\":\n" .. table.concat(errors, "\n"))
	end
end

_G.require = require

local GPUProxy = component.proxy(component.list("gpu")())
local screenWidth, screenHeight = GPUProxy.getResolution()

-- Displays title and currently required library when booting OS
local UIRequireTotal, UIRequireCounter = 14, 1

local function UIRequire(module)
	local function centrize(width)
		return math.floor(screenWidth / 2 - width / 2)
	end
	
	local title, width, total = "MineOS", 26, 14
	local x, y, part = centrize(width), math.floor(screenHeight / 2 - 1), math.ceil(width * UIRequireCounter / UIRequireTotal)
	UIRequireCounter = UIRequireCounter + 1
	
	-- Title
	GPUProxy.setForeground(colors.black)
	GPUProxy.set(centrize(#title), y, title)

	-- Progressbar
	GPUProxy.setForeground(colors.gray)
	GPUProxy.set(x, y + 2, string.rep("─", part))
	GPUProxy.setForeground(colors.lightGray)
	GPUProxy.set(x + part, y + 2, string.rep("─", width - part))

	return require(module)
end

-- Preparing screen for loading libraries
GPUProxy.setBackground(colors.white)
GPUProxy.fill(1, 1, screenWidth, screenHeight, " ")

-- Loading libraries
bit32 = bit32 or UIRequire("Bit32")
local paths = UIRequire("Paths")
local event = UIRequire("Event")
local filesystem = UIRequire("Filesystem")

-- Setting main filesystem proxy to what are we booting from
filesystem.setProxy(bootFilesystemProxy)

-- Replacing requireExists function after filesystem library initialization
requireExists = filesystem.exists

-- Loading other libraries
UIRequire("Component")
UIRequire("Keyboard")
UIRequire("Color")
UIRequire("Text")
UIRequire("Number")
local image = UIRequire("Image")
local screen = UIRequire("Screen")

-- Setting currently chosen GPU component as screen buffer main one
screen.setGPUProxy(GPUProxy)

local GUI = UIRequire("GUI")
local system = UIRequire("System")
UIRequire("Network")


-- Filling package.loaded with default global variables for OpenOS bitches
package.loaded.bit32 = bit32
package.loaded.computer = computer
package.loaded.component = component
package.loaded.unicode = unicode

---------------------------------------- Main loop ----------------------------------------

-- Creating OS workspace, which contains every window/menu/etc.
local workspace = GUI.workspace()
system.setWorkspace(workspace)

-- "double_touch" event handler
local doubleTouchInterval, doubleTouchX, doubleTouchY, doubleTouchButton, doubleTouchUptime, doubleTouchcomponentAddress = 0.3
event.addHandler(
	function(signalType, componentAddress, x, y, button, user)
		if signalType == "touch" then
			local uptime = computer.uptime()
			
			if doubleTouchX == x and doubleTouchY == y and doubleTouchButton == button and doubleTouchcomponentAddress == componentAddress and uptime - doubleTouchUptime <= doubleTouchInterval then
				computer.pushSignal("double_touch", componentAddress, x, y, button, user)
				event.skip("touch")
			end

			doubleTouchX, doubleTouchY, doubleTouchButton, doubleTouchUptime, doubleTouchcomponentAddress = x, y, button, uptime, componentAddress
		end
	end
)

-- Screen component attaching/detaching event handler
event.addHandler(
	function(signalType, componentAddress, componentType)
		if (signalType == "component_added" or signalType == "component_removed") and componentType == "screen" then
			local GPUProxy = screen.getGPUProxy()

			local function bindScreen(address)
				screen.bind(address, false)
				GPUProxy.setDepth(GPUProxy.maxDepth())
				workspace:draw()
			end

			if signalType == "component_added" then
				if not GPUProxy.getScreen() then
					bindScreen(componentAddress)
				end
			else
				if not GPUProxy.getScreen() then
					local address = component.list("screen")()
					
					if address then
						bindScreen(address)
					end
				end
			end
		end
	end
)

-- Logging in
system.authorize()


-- Main loop with UI regeneration after errors 
while true do
	local success, path, line, traceback = system.call(workspace.start, workspace, 0)
	
	if success then
		break
	else
		system.updateWorkspace()
		system.updateDesktop()
		workspace:draw()
		
		system.error(path, line, traceback)
		workspace:draw()
	end
end
