local Hangman = {}
Hangman.__index = Hangman

function Hangman.new(words, maxErrors)
    local self = setmetatable({}, Hangman)

    self.secretWord = words[math.random(#words)]
    self.maxErrors = maxErrors or 5
    self.errorCount = 0
    self.triedLetters = {}
    self.state = {}

    for i = 1, #self.secretWord do
        self.state[i] = "*"
    end

    return self
end

function Hangman:guess(letter)
    if #letter ~= 1 or not letter:match("%a") then
        return "invalid"
    end

    if self.triedLetters[letter] then
        return "repeated"
    end
    self.triedLetters[letter] = true

    local found = false
    for i = 1, #self.secretWord do
        if self.secretWord:sub(i, i) == letter then
            self.state[i] = letter
            found = true
        end
    end

    if found then
        return "hit"
    end

    self.errorCount = self.errorCount + 1
    return "miss"
end

function Hangman:isWon()
    for i = 1, #self.state do
        if self.state[i] == "*" then
            return false
        end
    end
    return true
end

function Hangman:isLost()
    return self.errorCount >= self.maxErrors
end

function Hangman:isOver()
    return self:isWon() or self:isLost()
end

function Hangman:getMaskedWord()
    return table.concat(self.state, " ")
end

function Hangman:getTriedLetters()
    local list = {}
    for letter in pairs(self.triedLetters) do
        list[#list + 1] = letter
    end
    table.sort(list)
    return table.concat(list, " ")
end

local ConsoleGame = {}
ConsoleGame.__index = ConsoleGame

local MESSAGES = {
    invalid = "Digite apenas uma letra (a-z)!",
    repeated = "Voce ja tentou essa letra! Escolha outra.",
    hit = "Voce acertou uma letra.",
    miss = "Letra incorreta!",
}

function ConsoleGame.new(game)
    local self = setmetatable({}, ConsoleGame)
    self.game = game
    return self
end

function ConsoleGame:showStatus()
    print("Palavra: " .. self.game:getMaskedWord())
    print("Tentadas: " .. self.game:getTriedLetters())
    print("Erros: " .. self.game.errorCount .. "/" .. self.game.maxErrors)
end

function ConsoleGame:readLetter()
    io.write("Digite sua letra: ")
    local input = io.read()
    if input == nil then
        return nil
    end
    return input:lower()
end

function ConsoleGame:showResult()
    if self.game:isWon() then
        print("Parabens! Voce descobriu a palavra: " .. self.game.secretWord)
    else
        print("Voce perdeu! A palavra era: " .. self.game.secretWord)
    end
end

function ConsoleGame:run()
    while not self.game:isOver() do
        self:showStatus()

        local letter = self:readLetter()
        if letter == nil then
            print("\nEntrada encerrada.")
            return
        end

        local result = self.game:guess(letter)
        print(MESSAGES[result])
        print()
    end

    self:showResult()
end

math.randomseed(os.time())

local words = {"chinchila", "dromedario", "escaravelho", "ornitorrinco", "percevejo"}

local game = Hangman.new(words, 5)
local console = ConsoleGame.new(game)
console:run()