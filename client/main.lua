local socket = require("socket")
local poll = require("posix.poll")
local json = require("json")

local HOST = os.getenv("FORCA_HOST") or "127.0.0.1"
local PORT = tonumber(os.getenv("FORCA_PORT")) or 12345

local function sendMessage(udp, message)
    udp:send(json.encode(message))
end

local function receiveMessage(udp)
    local data, err = udp:receive()
    if not data then
        return nil, err
    end

    local ok, decoded = pcall(json.decode, data)
    if not ok then
        return nil, "json invalido"
    end

    return decoded
end

local function waitForMessage(udp, timeoutSeconds)
    udp:settimeout(timeoutSeconds)
    return receiveMessage(udp)
end

local playerId = nil
local wordLength = 0
local currentStateStr = ""
local errorCount = 0
local triedLetters = {}
local gameOver = false

local function showState()
    io.write("Palavra: ")
    for letter in currentStateStr:gmatch(".") do
        io.write(letter, " ")
    end
    print()

    io.write("Tentadas: ")
    for _, letter in ipairs(triedLetters) do
        io.write(letter, " ")
    end
    print()

    io.write("Erros: ", errorCount, "/5\n")
end

local function applyUpdate(message)
    currentStateStr = message.state
    errorCount = message.errorCount
    triedLetters = message.triedLetters or {}

    if message.lastPlayer == playerId then
        if message.correct then
            print("Voce tentou '" .. message.letter .. "' e acertou!")
        else
            print("Voce tentou '" .. message.letter .. "' e errou.")
        end
    else
        if message.correct then
            print("Jogador " .. tostring(message.lastPlayer) .. " tentou '" ..
                message.letter .. "' e acertou!")
        else
            print("Jogador " .. tostring(message.lastPlayer) .. " tentou '" ..
                message.letter .. "' e errou.")
        end
    end
    print("Palavra agora: " .. currentStateStr:gsub(".", "%0 "))
end

local function applyGameOver(message)
    gameOver = true
    print()
    if message.won then
        print("Parabens! A palavra foi descoberta: " .. message.word)
    else
        print("Fim de jogo! O grupo perdeu. A palavra era: " .. message.word)
    end
end

local function handleServerMessage(message)
    if message.type == "update" then
        applyUpdate(message)
    elseif message.type == "gameOver" then
        applyGameOver(message)
    elseif message.type == "error" then
        print("Servidor: " .. tostring(message.message))
    end
end

local function joinGame(udp)
    local attempts = 0
    local maxAttempts = 10

    while attempts < maxAttempts do
        sendMessage(udp, { type = "join" })

        local message = waitForMessage(udp, 1)
        if message and message.type == "joined" then
            return message.playerId, message.totalPlayers
        end

        attempts = attempts + 1
        print("Aguardando resposta do servidor... (tentativa " .. attempts .. ")")
    end

    error("Nao foi possivel conectar ao servidor em " .. HOST .. ":" .. PORT)
end

local function waitForStart(udp)
    print("Aguardando outros jogadores entrarem na partida...")
    while true do
        local message = waitForMessage(udp, 5)
        if message and message.type == "start" then
            wordLength = message.wordLength
            currentStateStr = string.rep("_", wordLength)
            return
        end
    end
end

local function showPrompt()
    io.write("Digite sua letra: ")
    io.flush()
end

local function processGuessInput(udp, input)
    local letter = input:lower()

    if #letter ~= 1 or not letter:match("%a") then
        print("Digite apenas uma letra (a-z)!")
        return false
    end

    sendMessage(udp, { type = "guess", playerId = playerId, letter = letter })
    return true
end

local function drainAndHandle(udp)
    local receivedSomething = false
    udp:settimeout(0)

    local message = receiveMessage(udp)
    while message do
        receivedSomething = true
        handleServerMessage(message)
        if gameOver then
            return receivedSomething
        end
        message = receiveMessage(udp)
    end

    return receivedSomething
end

local function mainLoop(udp)
    local fd = math.floor(udp:getfd())

    print()
    showState()
    showPrompt()

    while not gameOver do
        local fds = {
            [0] = { events = { IN = true } },
            [fd] = { events = { IN = true } },
        }

        poll.poll(fds, 200)

        local receivedSomething = false

        if fds[fd].revents and fds[fd].revents.IN then
            receivedSomething = drainAndHandle(udp)
        end

        if not gameOver and fds[0].revents and fds[0].revents.IN then
            local input = io.read()
            if input == nil then
                print("\nEntrada encerrada, saindo.")
                return
            end

            local sent = processGuessInput(udp, input)
            if not sent then
                showPrompt()
            end
        end

        if not gameOver and receivedSomething then
            print()
            showState()
            showPrompt()
        end
    end
end


local function main()
    io.stdout:setvbuf("line") 

    local udp = socket.udp()
    udp:setpeername(HOST, PORT)

    local id, totalPlayers = joinGame(udp)
    playerId = id
    print("Voce entrou como jogador " .. playerId .. " (" .. totalPlayers .. "/3)")

    waitForStart(udp)
    print("O jogo comecou! Palavra com " .. wordLength .. " letras.")

    mainLoop(udp)

    udp:close()
end

main()