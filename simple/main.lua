local function drawWord(words)
    local index = math.random(#words)
    return words[index]
end

local function createState(word)
    local t = {}
    local n = #word
    for i = 1, n do
        t[i] = "*"
    end
    return t
end

local function isWordComplete(state)
    for i = 1, #state do
        if state[i] == "*" then
            return false
        end
    end

    return true
end

local function showWord(state)
    for _, l in ipairs(state) do
        io.write(l, " ")
    end
    print()
end

local function showTriedLetters(triedLetters)
    io.write("Tentadas: ")
    for l, _ in pairs(triedLetters) do
        io.write(l, " ")
    end
    print()
end

local function tryLetter(word, letter, state)
    local found = false

    for i = 1, #word do
        if word:sub(i, i) == letter then
            state[i] = letter
            found = true
        end
    end

    return found
end

local function markLetterAsTried(triedLetters, letter)
    triedLetters[letter] = true
end

local function isLetterTried(triedLetters, letter)
    return triedLetters[letter] == true
end

math.randomseed(os.time())
local words = {"chinchila", "dromedário", "escaravelho", "ornitorrinco", "percevejo"}
local secretWord = drawWord(words)

--print(secretWord)

local errorCount = 0
local currentState = createState(secretWord)
local triedLetters = {}

while not isWordComplete(currentState) and errorCount < 5 do
    io.write("Palavra: ")
    showWord(currentState)
    showTriedLetters(triedLetters)
    io.write("Erros: ", errorCount, "/5\n")
    io.write("Digite sua letra: ")
    local letter = io.read():lower()
    if #letter ~= 1 or not letter:match("%a") then
        print("Digite apenas uma letra (a-z)!")
    elseif isLetterTried(triedLetters, letter) then
        print("Voce ja tentou essa letra! Escolha outra.")
    else
        markLetterAsTried(triedLetters, letter)
        if not tryLetter(secretWord, letter, currentState) then
            errorCount = errorCount + 1
            print("Letra incorreta!")
        else
            print("Voce acertou uma letra.")
        end
    end
    print()
end

if isWordComplete(currentState) then
    print("Parabens! Voce descobriu a palavra: " .. secretWord)
else
    print("Voce perdeu! A palavra era: " .. secretWord)
end