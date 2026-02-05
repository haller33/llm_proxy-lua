local http_server = require "http.server"
local http_request = require "http.request"
local json = require "cjson"
local pgmoon = require "pgmoon"

-- --- CONFIGURATION ---
local DB_CONFIG = {
  host = os.getenv("DB_HOST") or "db",
  port = os.getenv("DB_PORT") or 5432,
  database = os.getenv("DB_NAME") or "analytic_db",
  user = os.getenv("DB_USER") or "admin",
  password = os.getenv("DB_PASS") or "your_password"
}
local OLLAMA_URL = os.getenv("OLLAMA_URL") or "http://ollama:11434/api/generate"

local function save_to_db(model, prompt, response, p_tokens, c_tokens, t_ns, e_ns)
    local pg = pgmoon.new(DB_CONFIG)
    local ok, err = pg:connect()
    if not ok then return print("DB Connection Error: " .. err) end

    local query = string.format(
        "INSERT INTO ollama_logs (model_name, prompt_sent, response_received, prompt_tokens, completion_tokens, total_tokens, total_duration_ns, eval_duration_ns) VALUES (%s, %s, %s, %d, %d, %d, %s, %s)",
        pg:escape_literal(model),
        pg:escape_literal(prompt),
        pg:escape_literal(response),
        p_tokens,
        c_tokens,
        p_tokens + c_tokens,
        t_ns,
        e_ns
    )
    
    pg:query(query)
    pg:keepalive()
end

local function handle_request(myserver, stream)
    local headers = stream:get_headers()
    local method = headers:get(":method")

    if method == "POST" then
        local body = stream:get_body_as_string()
        local input = json.decode(body)
        
        -- Forward to Ollama
        local req = http_request.new_from_uri(OLLAMA_URL)
        req.headers:upsert(":method", "POST")
        req.headers:upsert("content-type", "application/json")
        
        local ollama_payload = json.encode({
            model = input.model or "llama3.2",
            prompt = input.prompt,
            stream = false
        })
        req:set_body(ollama_payload)

        local res_headers, res_stream = req:go()
        local res_body = res_stream:get_body_as_string()
        local ollama_res = json.decode(res_body)

        -- Async-ish log to DB
        save_to_db(
            input.model, 
            input.prompt, 
            ollama_res.response,
            ollama_res.prompt_eval_count or 0,
            ollama_res.eval_count or 0,
            ollama_res.total_duration or 0,
            ollama_res.eval_duration or 0
        )

        -- Return to client
        stream:write_headers(res_headers, false)
        stream:write_body_from_string(res_body)
    end
end

local server = http_server.listen {
    host = "0.0.0.0",
    port = 5000,
    onstream = handle_request,
}

print("Lua Proxy Server running on port 5000...")
server:loop()
