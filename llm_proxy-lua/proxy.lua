local http_server = require "http.server"
local http_request = require "http.request"
local json = require "cjson"
local pgmoon = require "pgmoon"

-- Initialize PG outside to reuse connection parameters
local DB_CONFIG = {
  host = os.getenv("DB_HOST") or "db",
  port = os.getenv("DB_PORT") or 5432,
  database = os.getenv("DB_NAME") or "analytic_db",
  user = os.getenv("DB_USER") or "admin",
  password = os.getenv("DB_PASS") or "your_password"
}
local OLLAMA_URL = os.getenv("OLLAMA_URL") or "http://ollama:11434/api/generate"

-- Shared PG instance
local pg = pgmoon.new(DB_CONFIG)

local function save_to_db(model, prompt, response, p_tokens, c_tokens, t_ns, e_ns)
    -- Simple connect/check
    local ok, err = pg:connect()
    if not ok then 
        print("DB Connection Error: " .. tostring(err))
        return 
    end

    -- Use %d for numbers or pg:escape_literal for everything to be safe
    local query = string.format(
        "INSERT INTO ollama_logs (model_name, prompt_sent, response_received, prompt_tokens, completion_tokens, total_tokens, total_duration_ns, eval_duration_ns) VALUES (%s, %s, %s, %d, %d, %d, %s, %s)",
        pg:escape_literal(model or "unknown"),
        pg:escape_literal(prompt or ""),
        pg:escape_literal(response or ""),
        p_tokens or 0,
        c_tokens or 0,
        (p_tokens or 0) + (c_tokens or 0),
        pg:escape_literal(tostring(t_ns or 0)), -- Nanoseconds as strings to prevent Lua 5.1 overflow
        pg:escape_literal(tostring(e_ns or 0))
    )
    
    pg:query(query)
    pg:keepalive()
end

local function handle_request(myserver, stream)
    local headers = stream:get_headers()
    local method = headers:get(":method")

    if method ~= "POST" then
        stream:write_headers(http_server.new_headers{ [":status"] = "405" }, true)
        return
    end

    local body = stream:get_body_as_string()
    local success, input = pcall(json.decode, body)
    if not success or not input.prompt then
        stream:write_headers(http_server.new_headers{ [":status"] = "400" }, false)
        stream:write_body_from_string("Invalid JSON or missing prompt")
        return
    end

    -- Forward to Ollama
    local req = http_request.new_from_uri(OLLAMA_URL)
    req.headers:upsert(":method", "POST")
    req.headers:upsert("content-type", "application/json")
    
    req:set_body(json.encode({
        model = input.model or "llama3.2",
        prompt = input.prompt,
        stream = false
    }))

    local res_headers, res_stream = req:go(10) -- Added 10s timeout
    if not res_headers then
        stream:write_headers(http_server.new_headers{ [":status"] = "504" }, true)
        return
    end

    local res_body = res_stream:get_body_as_string()
    local ok_res, ollama_res = pcall(json.decode, res_body)

    if ok_res then
        -- Log to DB
        save_to_db(
            input.model, 
            input.prompt, 
            ollama_res.response,
            ollama_res.prompt_eval_count,
            ollama_res.eval_count,
            ollama_res.total_duration,
            ollama_res.eval_duration
        )
    end

    -- Return to client
    stream:write_headers(res_headers, false)
    stream:write_body_from_string(res_body)
end

local server = http_server.listen {
    host = "0.0.0.0",
    port = 5000,
    onstream = handle_request,
}

print("Lua Proxy Server running on port 5000...")
server:loop()
