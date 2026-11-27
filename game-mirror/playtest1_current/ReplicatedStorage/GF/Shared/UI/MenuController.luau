--!strict
-- MenuController: cross-script access to the operations menu shell. client scripts each own
-- their environments; this shared registry is how terminal-proximity detection (StationUI)
-- opens the deploy surface that lives in SquadBrowser without either owning the other.
local MenuController = {
	_shell = nil :: any,
}

function MenuController.register(shell: any)
	MenuController._shell = shell
end

function MenuController.open(section: string?)
	local shell = MenuController._shell
	if not shell then return end
	if not shell.visible then
		shell:open()
	end
	if section then
		shell:setActive(section)
	end
end

function MenuController.close()
	local shell = MenuController._shell
	if shell then shell:close() end
end

function MenuController.isOpen(): boolean
	local shell = MenuController._shell
	return shell ~= nil and shell.visible == true
end

function MenuController.setRegionFilter(regions: string?)
	-- terminal arc preselection: the deploy section reads this on open
	local shell = MenuController._shell
	if shell then
		shell._terminalRegions = regions
	end
end

return MenuController
