--!native
--!optimize 2

--[[
	Host.luau

	Provides the renderer host table and resets runtime callback fields.
]]

type Host = {
	getThinkerCap: unknown?,
	mobjThinker: unknown?,
	netUpdate: unknown?,
	Reset: (() -> ())?,
}

const host: Host = {}

const function Reset()
	host.getThinkerCap = nil
	host.mobjThinker = nil
	host.netUpdate = nil
end

Reset()

host.Reset = Reset

return host
