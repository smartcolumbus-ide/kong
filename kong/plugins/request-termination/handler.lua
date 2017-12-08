local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local meta = require "kong.meta"

local server_header = meta._NAME .. "/" .. meta._VERSION

local RequestTerminationHandler = BasePlugin:extend()

RequestTerminationHandler.PRIORITY = 7
RequestTerminationHandler.VERSION = "0.1.0"

local function write(ctx)
  local res = ctx.req_term_res

  ngx.status = res.status

  ngx.header["Content-Type"] = res.ct
  ngx.header["Server"] = res.server

  ngx.say(res.body)

  return ngx.exit(res.status)
end

function RequestTerminationHandler:new()
  RequestTerminationHandler.super.new(self, "request-termination")
end

function RequestTerminationHandler:access(conf)
  RequestTerminationHandler.super.access(self)

  local status_code = conf.status_code
  local content_type = conf.content_type
  local body = conf.body
  local message = conf.message
  if body then
    ngx.ctx.req_term_res = {
      status = status_code,
      ct = content_type or "application/json; charset=utf-8",
      server = server_header,
      body = body,
    }

    ngx.ctx.delayed_response = true --mock
    ngx.ctx.delayed_response_callback = write
   else
    return responses.send(status_code, message)
  end
end

return RequestTerminationHandler
