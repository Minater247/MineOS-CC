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
	[0xffffff] = colors.white,
	[0x2d2d2d] = colors.black,
	[0x878787] = colors.gray,
	[0xc3c3c3] = colors.lightGray
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
fsproxyinternal.spaceTotal = function()
	return math.huge
end
fsproxyinternal.makeDirectory = fs.makeDir
fsproxyinternal.open = fs.open
fsproxyinternal.write = function(stream, chunk)
	returnval = stream.write(chunk)
	return returnval
end
fsproxyinternal.close = function(stream)
	return stream.close()
end
fsproxyinternal.read = function(stream, stopPoint)
	local streamData = stream.readAll()
	--if stopPoint is math.huge, return the whole thing
	if stopPoint == math.huge then
		return streamData
	end
	--otherwise, return the first stopPoint characters
	if stopPoint then
		return string.sub(streamData, 1, stopPoint)
	else
		return streamData
	end
end


local internetproxy = http

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
	elseif name == "internet" then
		table.insert(sidesWithComponent, "http")
	end
	return tableToIter(sidesWithComponent)
end
component.proxy = function(side)
	if side == "internalmonitor" then
		return gputerm
	elseif side == "internaldrive" then
		return fsproxyinternal
	elseif side == "http" then
		return internetproxy
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

------------------------------------------- MineOS Installer ------------------------------------------

-- Checking for required components
local function getComponentAddress(name)
	return component.list(name)() or error("Required " .. name .. " component is missing")
end

local function getComponentProxy(name)
	return component.proxy(getComponentAddress(name))
end

local internetProxy, GPUProxy = 
	getComponentProxy("internet"),
	getComponentProxy("gpu")

local screenWidth, screenHeight = GPUProxy.getResolution()
local repositoryURL = "https://raw.githubusercontent.com/Minater247/MineOS-CC/master/"
local installerURL = "Installer/"
local EFIURL = "EFI/Minified.lua"

local installerPath = "/MineOS installer/"
local installerPicturesPath = installerPath .. "Installer/Pictures/"
local OSPath = "/"

local temporaryFilesystemProxy, selectedFilesystemProxy

--------------------------------------------------------------------------------

-- Working with components directly before system libraries are downloaded & initialized
local function centrize(width)
	return math.floor(screenWidth / 2 - width / 2)
end

local function centrizedText(y, color, text)
	GPUProxy.fill(1, y, screenWidth, 1, " ")
	GPUProxy.setForeground(color)
	GPUProxy.set(centrize(#text), y, text)
end

local function title()
	local y = math.floor(screenHeight / 2 - 1)
	centrizedText(y, 0x2D2D2D, "MineOS")

	return y + 2
end

local function status(text, needWait)
	centrizedText(title(), 0x878787, text)

	if needWait then
		repeat
			needWait = computer.pullSignal()
		until needWait == "key_down" or needWait == "touch"
	end
end

local function progress(value)
	local width = 26
	local x, y, part = centrize(width), title(), math.ceil(width * value)
	
	GPUProxy.setForeground(0x878787)
	GPUProxy.set(x, y, string.rep("???", part))
	GPUProxy.setForeground(0xC3C3C3)
	GPUProxy.set(x + part, y, string.rep("???", width - part))
end

local function filesystemPath(path)
	return path:match("^(.+%/).") or ""
end

local function filesystemName(path)
	return path:match("%/?([^%/]+%/?)$")
end

local function filesystemHideExtension(path)
	return path:match("(.+)%..+") or path
end

local function rawRequest(url, chunkHandler)
	local internetHandle = internetProxy.get(repositoryURL .. url:gsub("([^%w%-%_%.%~])", function(char)
		return string.format("%%%02X", string.byte(char))
	end))

	if internetHandle then
		local chunk, reason
		while true do
			chunk, reason = internetHandle.readAll()
			
			if chunk then
				chunkHandler(chunk)
			else
				if reason then
					error("Internet request failed: " .. tostring(reason))
				end

				break
			end
		end

		internetHandle.close()
	else
		error("Connection failed: " .. url)
	end
end

local function request(url)
	local data = ""
	
	rawRequest(url, function(chunk)
		data = data .. chunk
	end)

	return data
end

local function download(url, path)
	selectedFilesystemProxy.makeDirectory(filesystemPath(path))

	local fileHandle, reason = selectedFilesystemProxy.open(path, "wb")
	if fileHandle then
		rawRequest(url, function(chunk)
			selectedFilesystemProxy.write(fileHandle, chunk)
		end)

		selectedFilesystemProxy.close(fileHandle)
	else
		error("File opening failed: " .. tostring(reason))
	end
end

local function deserialize(text)
	local result, reason = load("return " .. text, "=string")
	if result then
		return result()
	else
		error(reason)
	end
end

-- Clearing screen
GPUProxy.setBackground(0xE1E1E1)
GPUProxy.fill(1, 1, screenWidth, screenHeight, " ")

-- Searching for appropriate temporary filesystem for storing libraries, images, etc
for address in component.list("filesystem") do
	local proxy = component.proxy(address)
	if proxy.spaceTotal() >= 2 * 1024 * 1024 then
		temporaryFilesystemProxy, selectedFilesystemProxy = proxy, proxy
		break
	end
end

-- If there's no suitable HDDs found - then meow
if not temporaryFilesystemProxy then
	status("No appropriate filesystem found", true)
	return
end

-- First, we need a big file list with localizations, applications, wallpapers
progress(0)
local files = deserialize(request(installerURL .. "Files.cfg"))

-- After that we could download required libraries for installer from it
for i = 1, #files.installerFiles do
	progress(i / #files.installerFiles)
	if not fs.exists(installerPath .. files.installerFiles[i]) then
		download(files.installerFiles[i], installerPath .. files.installerFiles[i])
	end
end


-- Initializing simple package system for loading system libraries
package = {loading = {}, loaded = {}}

function require(module)
	if package.loaded[module] then
		return package.loaded[module]
	elseif package.loading[module] then
		error("already loading " .. module .. ": " .. debug.traceback())
	else
		package.loading[module] = true

		local handle, reason = temporaryFilesystemProxy.open(installerPath .. "Libraries/" .. module .. ".lua", "rb")
		if handle then
			local data, chunk = ""
			repeat
				chunk = temporaryFilesystemProxy.read(handle, math.huge)
				data = data .. (chunk or "")
			until not chunk

			temporaryFilesystemProxy.close(handle)
			
			local result, reason = load(data, "=" .. module)
			if result then
				package.loaded[module] = result() or true
			else
				error(reason)
			end
		else
			error("File opening failed: " .. tostring(reason))
		end

		package.loading[module] = nil

		return package.loaded[module]
	end
end

_G.require = require

-- Initializing system libraries
local filesystem = require("Filesystem")
filesystem.setProxy(temporaryFilesystemProxy)

bit32 = bit32 or require("Bit32")
local image = require("Image")
local text = require("Text")
local number = require("Number")

local screen = require("Screen")
screen.setGPUProxy(GPUProxy)

local GUI = require("GUI")
local system = require("System")
local paths = require("Paths")

--------------------------------------------------------------------------------

-- Creating main UI workspace
local workspace = GUI.workspace()
workspace:addChild(GUI.panel(1, 1, workspace.width, workspace.height, 0x1E1E1E))

-- Main installer window
local window = workspace:addChild(GUI.window(1, 1, 80, 24))
window.localX, window.localY = math.ceil(workspace.width / 2 - window.width / 2), math.ceil(workspace.height / 2 - window.height / 2)
window:addChild(GUI.panel(1, 1, window.width, window.height, 0xE1E1E1))

-- Top menu
local menu = workspace:addChild(GUI.menu(1, 1, workspace.width, 0xF0F0F0, 0x787878, 0x3366CC, 0xE1E1E1))
local installerMenu = menu:addContextMenuItem("MineOS", 0x2D2D2D)
installerMenu:addItem("Shutdown").onTouch = function()
	computer.shutdown()
end
installerMenu:addItem("Reboot").onTouch = function()
	computer.shutdown(true)
end
installerMenu:addSeparator()
installerMenu:addItem("Exit").onTouch = function()
	workspace:stop()
end

-- Main vertical layout
local layout = window:addChild(GUI.layout(1, 1, window.width, window.height - 2, 1, 1))

local stageButtonsLayout = window:addChild(GUI.layout(1, window.height - 1, window.width, 1, 1, 1))
stageButtonsLayout:setDirection(1, 1, GUI.DIRECTION_HORIZONTAL)
stageButtonsLayout:setSpacing(1, 1, 3)

local function loadImage(name)
	return image.load(installerPicturesPath .. name .. ".pic")
end

local function newInput(...)
	return GUI.input(1, 1, 26, 1, 0xF0F0F0, 0x787878, 0xC3C3C3, 0xF0F0F0, 0x878787, "", ...)
end

local function newSwitchAndLabel(width, color, text, state)
	return GUI.switchAndLabel(1, 1, width, 6, color, 0xD2D2D2, 0xF0F0F0, 0xA5A5A5, text .. ":", state)
end

local function addTitle(color, text)
	return layout:addChild(GUI.text(1, 1, color, text))
end

local function addImage(before, after, name)
	if before > 0 then
		layout:addChild(GUI.object(1, 1, 1, before))
	end

	local picture = layout:addChild(GUI.image(1, 1, loadImage(name)))
	picture.height = picture.height + after

	return picture
end

local function addStageButton(text)
	local button = stageButtonsLayout:addChild(GUI.adaptiveRoundedButton(1, 1, 2, 0, 0xC3C3C3, 0x878787, 0xA5A5A5, 0x696969, text))
	button.colors.disabled.background = 0xD2D2D2
	button.colors.disabled.text = 0xB4B4B4

	return button
end

local prevButton = addStageButton("<")
local nextButton = addStageButton(">")

local localization
local stage = 1
local stages = {}

local usernameInput = newInput("")
local passwordInput = newInput("", false, "???")
local passwordSubmitInput = newInput("", false, "???")
local usernamePasswordText = GUI.text(1, 1, 0xCC0040, "")
local passwordSwitchAndLabel = newSwitchAndLabel(26, 0x66DB80, "", false)

local wallpapersSwitchAndLabel = newSwitchAndLabel(30, 0xFF4980, "", true)
local screensaversSwitchAndLabel = newSwitchAndLabel(30, 0xFFB600, "", true)
local applicationsSwitchAndLabel = newSwitchAndLabel(30, 0x33DB80, "", true)
local localizationsSwitchAndLabel = newSwitchAndLabel(30, 0x33B6FF, "", true)

local acceptSwitchAndLabel = newSwitchAndLabel(30, 0x9949FF, "", false)

local localizationComboBox = GUI.comboBox(1, 1, 22, 1, 0xF0F0F0, 0x969696, 0xD2D2D2, 0xB4B4B4)
for i = 1, #files.localizations do
	localizationComboBox:addItem(filesystemHideExtension(filesystemName(files.localizations[i]))).onTouch = function()
		-- Obtaining localization table
		localization = deserialize(request(installerURL .. files.localizations[i]))

		-- Filling widgets with selected localization data
		usernameInput.placeholderText = localization.username
		passwordInput.placeholderText = localization.password
		passwordSubmitInput.placeholderText = localization.submitPassword
		passwordSwitchAndLabel.label.text = localization.withoutPassword
		wallpapersSwitchAndLabel.label.text = localization.wallpapers
		screensaversSwitchAndLabel.label.text = localization.screensavers
		applicationsSwitchAndLabel.label.text = localization.applications
		localizationsSwitchAndLabel.label.text = localization.languages
		acceptSwitchAndLabel.label.text = localization.accept
	end
end

local function addStage(onTouch)
	table.insert(stages, function()
		layout:removeChildren()
		onTouch()
		workspace:draw()
	end)
end

local function loadStage()
	if stage < 1 then
		stage = 1
	elseif stage > #stages then
		stage = #stages
	end

	stages[stage]()
end

local function checkUserInputs()
	local nameEmpty = #usernameInput.text == 0
	local nameVaild = usernameInput.text:match("^%w[%w%s_]+$")
	local passValid = passwordSwitchAndLabel.switch.state or #passwordInput.text == 0 or #passwordSubmitInput.text == 0 or passwordInput.text == passwordSubmitInput.text

	if (nameEmpty or nameVaild) and passValid then
		usernamePasswordText.hidden = true
		nextButton.disabled = nameEmpty or not nameVaild or not passValid
	else
		usernamePasswordText.hidden = false
		nextButton.disabled = true

		if nameVaild then
			usernamePasswordText.text = localization.passwordsArentEqual
		else
			usernamePasswordText.text = localization.usernameInvalid
		end
	end
end

local function checkLicense()
	nextButton.disabled = not acceptSwitchAndLabel.switch.state
end

prevButton.onTouch = function()
	stage = stage - 1
	loadStage()
end

nextButton.onTouch = function()
	stage = stage + 1
	loadStage()
end

acceptSwitchAndLabel.switch.onStateChanged = function()
	checkLicense()
	workspace:draw()
end

passwordSwitchAndLabel.switch.onStateChanged = function()
	passwordInput.hidden = passwordSwitchAndLabel.switch.state
	passwordSubmitInput.hidden = passwordSwitchAndLabel.switch.state
	checkUserInputs()

	workspace:draw()
end

usernameInput.onInputFinished = function()
	checkUserInputs()
	workspace:draw()
end

passwordInput.onInputFinished = usernameInput.onInputFinished
passwordSubmitInput.onInputFinished = usernameInput.onInputFinished

-- Localization selection stage
addStage(function()
	prevButton.disabled = true

	addImage(0, 1, "Languages")
	layout:addChild(localizationComboBox)

	workspace:draw()
	localizationComboBox:getItem(1).onTouch()
end)

-- Filesystem selection stage
addStage(function()
	prevButton.disabled = false
	nextButton.disabled = false

	layout:addChild(GUI.object(1, 1, 1, 1))
	addTitle(0x696969, localization.select)
	
	local diskLayout = layout:addChild(GUI.layout(1, 1, layout.width, 11, 1, 1))
	diskLayout:setDirection(1, 1, GUI.DIRECTION_HORIZONTAL)
	diskLayout:setSpacing(1, 1, 0)

	local HDDImage = loadImage("HDD")

	local function select(proxy)
		selectedFilesystemProxy = proxy

		for i = 1, #diskLayout.children do
			diskLayout.children[i].children[1].hidden = diskLayout.children[i].proxy ~= selectedFilesystemProxy
		end
	end

	local function updateDisks()
		local function diskEventHandler(workspace, disk, e1)
			if e1 == "touch" then
				select(disk.proxy)
				workspace:draw()
			end
		end

		local function addDisk(proxy, picture, disabled)
			local disk = diskLayout:addChild(GUI.container(1, 1, 14, diskLayout.height))

			local formatContainer = disk:addChild(GUI.container(1, 1, disk.width, disk.height))
			formatContainer:addChild(GUI.panel(1, 1, formatContainer.width, formatContainer.height, 0xD2D2D2))
			formatContainer:addChild(GUI.button(1, formatContainer.height, formatContainer.width, 1, 0xCC4940, 0xE1E1E1, 0x990000, 0xE1E1E1, localization.erase)).onTouch = function()
				local list, path = proxy.list("/")
				for i = 1, #list do
					path = "/" .. list[i]

					if proxy.address ~= temporaryFilesystemProxy.address or path ~= installerPath then
						proxy.remove(path)
					end
				end

				updateDisks()
			end

			if disabled then
				picture = image.blend(picture, 0xFFFFFF, 0.4)
				disk.disabled = true
			end

			disk:addChild(GUI.image(4, 2, picture))
			disk:addChild(GUI.label(2, 7, disk.width - 2, 1, disabled and 0x969696 or 0x696969, text.limit(proxy.getLabel() or proxy.address, disk.width - 2))):setAlignment(GUI.ALIGNMENT_HORIZONTAL_CENTER, GUI.ALIGNMENT_VERTICAL_TOP)
			disk:addChild(GUI.progressBar(2, 8, disk.width - 2, disabled and 0xCCDBFF or 0x66B6FF, disabled and 0xD2D2D2 or 0xC3C3C3, disabled and 0xC3C3C3 or 0xA5A5A5, math.floor(proxy.spaceUsed() / proxy.spaceTotal() * 100), true, true, "", "% " .. localization.used))

			disk.eventHandler = diskEventHandler
			disk.proxy = proxy
		end

		diskLayout:removeChildren()
		
		for address in component.list("filesystem") do
			local proxy = component.proxy(address)
			if proxy.spaceTotal() >= 1 * 1024 * 1024 then
				addDisk(
					proxy,
					proxy.spaceTotal() < 1 * 1024 * 1024 and floppyImage or HDDImage,
					proxy.isReadOnly() or proxy.spaceTotal() < 2 * 1024 * 1024
				)
			end
		end

		select(selectedFilesystemProxy)
	end
	
	updateDisks()
end)

-- User profile setup stage
addStage(function()
	checkUserInputs()

	addImage(0, 0, "User")
	addTitle(0x696969, localization.setup)

	layout:addChild(usernameInput)
	layout:addChild(passwordInput)
	layout:addChild(passwordSubmitInput)
	layout:addChild(usernamePasswordText)
	layout:addChild(passwordSwitchAndLabel)
end)

-- Downloads customization stage
addStage(function()
	nextButton.disabled = false

	addImage(0, 0, "Settings")
	addTitle(0x696969, localization.customize)

	layout:addChild(wallpapersSwitchAndLabel)
	layout:addChild(screensaversSwitchAndLabel)
	layout:addChild(applicationsSwitchAndLabel)
	layout:addChild(localizationsSwitchAndLabel)
end)

-- License acception stage
addStage(function()
	checkLicense()

	local lines = text.wrap({request("LICENSE")}, layout.width - 2)
	local textBox = layout:addChild(GUI.textBox(1, 1, layout.width, layout.height - 3, 0xF0F0F0, 0x696969, lines, 1, 1, 1))

	layout:addChild(acceptSwitchAndLabel)
end)

-- Downloading stage
addStage(function()
	stageButtonsLayout:removeChildren()
	
	-- Creating user profile
	layout:removeChildren()
	addImage(1, 1, "User")
	addTitle(0x969696, localization.creating)
	workspace:draw()

	-- Renaming if possible
	if not selectedFilesystemProxy.getLabel() then
		selectedFilesystemProxy.setLabel("MineOS HDD")
	end

	local function switchProxy(runnable)
		filesystem.setProxy(selectedFilesystemProxy)
		runnable()
		filesystem.setProxy(temporaryFilesystemProxy)
	end

	-- Creating system paths
	local userSettings, userPaths
	switchProxy(function()
		paths.create(paths.system)
		userSettings, userPaths = system.createUser(
			usernameInput.text,
			localizationComboBox:getItem(localizationComboBox.selectedItem).text,
			not passwordSwitchAndLabel.switch.state and passwordInput.text,
			wallpapersSwitchAndLabel.switch.state,
			screensaversSwitchAndLabel.switch.state
		)
	end)

	-- Flashing EEPROM
	layout:removeChildren()
	addImage(1, 1, "EEPROM")
	addTitle(0x969696, localization.flashing)
	workspace:draw()
	
	EEPROMProxy.set(request(EFIURL))
	EEPROMProxy.setLabel("MineOS EFI")
	EEPROMProxy.setData(selectedFilesystemProxy.address)

	-- Downloading files
	layout:removeChildren()
	addImage(3, 2, "Downloading")

	local container = layout:addChild(GUI.container(1, 1, layout.width - 20, 2))
	local progressBar = container:addChild(GUI.progressBar(1, 1, container.width, 0x66B6FF, 0xD2D2D2, 0xA5A5A5, 0, true, false))
	local cyka = container:addChild(GUI.label(1, 2, container.width, 1, 0x969696, "")):setAlignment(GUI.ALIGNMENT_HORIZONTAL_CENTER, GUI.ALIGNMENT_VERTICAL_TOP)

	-- Creating final filelist of things to download
	local downloadList = {}

	local function getData(item)
		if type(item) == "table" then
			return item.path, item.id, item.version, item.shortcut
		else
			return item
		end
	end

	local function addToList(state, key)
		if state then
			local selectedLocalization, path, localizationName = localizationComboBox:getItem(localizationComboBox.selectedItem).text
			
			for i = 1, #files[key] do
				path = getData(files[key][i])

				if filesystem.extension(path) == ".lang" then
					localizationName = filesystem.hideExtension(filesystem.name(path))

					if
						-- If ALL loacalizations need to be downloaded
						localizationsSwitchAndLabel.switch.state or
						-- If it's required localization file
						localizationName == selectedLocalization or
						-- Downloading English "just in case" for non-english localizations
						selectedLocalization ~= "English" and localizationName == "English"
					then
						table.insert(downloadList, files[key][i])
					end
				else
					table.insert(downloadList, files[key][i])
				end
			end
		end
	end

	addToList(true, "required")
	addToList(true, "localizations")
	addToList(applicationsSwitchAndLabel.switch.state, "optional")
	addToList(wallpapersSwitchAndLabel.switch.state, "wallpapers")
	addToList(screensaversSwitchAndLabel.switch.state, "screensavers")

	-- Downloading files from created list
	local versions, path, id, version, shortcut = {}
	for i = 1, #downloadList do
		path, id, version, shortcut = getData(downloadList[i])

		cyka.text = text.limit(localization.installing .. " \"" .. path .. "\"", container.width, "center")
		workspace:draw()

		-- Download file
		download(path, OSPath .. path)

		-- Adding system versions data
		if id then
			versions[id] = {
				path = OSPath .. path,
				version = version or 1,
			}
		end

		-- Create shortcut if possible
		if shortcut then
			switchProxy(function()
				system.createShortcut(
					userPaths.desktop .. filesystem.hideExtension(filesystem.name(filesystem.path(path))),
					OSPath .. filesystem.path(path)
				)
			end)
		end

		progressBar.value = math.floor(i / #downloadList * 100)
		workspace:draw()
	end

	-- Saving system versions
	switchProxy(function()
		filesystem.writeTable(paths.system.versions, versions, true)
	end)

	-- Done info
	layout:removeChildren()
	addImage(1, 1, "Done")
	addTitle(0x969696, localization.installed)
	addStageButton(localization.reboot).onTouch = function()
		computer.shutdown(true)
	end
	workspace:draw()

	-- Removing temporary installer directory
	temporaryFilesystemProxy.remove(installerPath)
end)

--------------------------------------------------------------------------------

loadStage()
workspace:start()