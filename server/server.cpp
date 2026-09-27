#include <iostream>
#include <vector>
#include <set>
#include <string>
#include <cstring>
#include <cstdlib>
#include <cctype>
#include <ctime>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

#define UDP_PORT 12345
#define MAX_BUFFER_SIZE 2048
#define MAX_PLAYERS 3
#define MAX_ERRORS 5

struct Player {
    int id;
    sockaddr_in addr;
};

std::vector<std::string> wordList = {
    "chinchila", "dromedario", "escaravelho", "ornitorrinco", "jamelao"
};

std::string secretWord;
std::vector<char> currentState;
int errorCount = 0;
std::set<char> triedLetters;
bool gameStarted = false;
bool gameOver = false;

std::vector<Player> players;
int sockUDP;

std::string drawWord() {
    int index = rand() % (int) wordList.size();
    return wordList[index];
}

std::vector<char> createState(const std::string &word) {
    return std::vector<char>(word.size(), '*');
}

bool isWordComplete(const std::vector<char> &state) {
    for (char c : state) {
        if (c == '*') return false;
    }
    return true;
}

bool tryLetter(const std::string &word, char letter, std::vector<char> &state) {
    bool found = false;
    for (size_t i = 0; i < word.size(); i++) {
        if (word[i] == letter) {
            state[i] = letter;
            found = true;
        }
    }
    return found;
}

std::string stateToString(const std::vector<char> &state) {
    return std::string(state.begin(), state.end());
}

json triedLettersToJson() {
    json arr = json::array();
    for (char c : triedLetters) {
        arr.push_back(std::string(1, c));
    }
    return arr;
}

bool sameAddress(const sockaddr_in &a, const sockaddr_in &b) {
    return a.sin_addr.s_addr == b.sin_addr.s_addr && a.sin_port == b.sin_port;
}

int findPlayerByAddr(const sockaddr_in &addr) {
    for (size_t i = 0; i < players.size(); i++) {
        if (sameAddress(players[i].addr, addr)) {
            return (int) i;
        }
    }
    return -1;
}

void sendJSON(const sockaddr_in &addr, const json &message) {
    std::string data = message.dump();
    sendto(sockUDP, data.c_str(), data.size(), 0, (struct sockaddr *) &addr, sizeof(addr));
}

void broadcast(const json &message) {
    for (const Player &p : players) {
        sendJSON(p.addr, message);
    }
}

void sendErrorTo(const sockaddr_in &addr, const std::string &text) {
    json msg;
    msg["type"] = "error";
    msg["message"] = text;
    sendJSON(addr, msg);
}

void startGame() {
    secretWord = drawWord();
    currentState = createState(secretWord);
    errorCount = 0;
    triedLetters.clear();
    gameStarted = true;
    gameOver = false;

    std::cout << "Jogo iniciado! Palavra secreta: " << secretWord << std::endl;

    json msg;
    msg["type"] = "start";
    msg["wordLength"] = (int) secretWord.size();
    broadcast(msg);
}

void handleJoin(const sockaddr_in &clientAddr) {
    int existing = findPlayerByAddr(clientAddr);
    if (existing != -1) {
        json msg;
        msg["type"] = "joined";
        msg["playerId"] = players[existing].id;
        msg["totalPlayers"] = (int) players.size();
        sendJSON(clientAddr, msg);
        return;
    }

    if ((int) players.size() >= MAX_PLAYERS || gameStarted) {
        sendErrorTo(clientAddr, "Sala cheia ou jogo ja iniciado");
        return;
    }

    Player newPlayer;
    newPlayer.id = (int) players.size() + 1;
    newPlayer.addr = clientAddr;
    players.push_back(newPlayer);

    std::cout << "Jogador " << newPlayer.id << " entrou ("
              << players.size() << "/" << MAX_PLAYERS << ")" << std::endl;

    json msg;
    msg["type"] = "joined";
    msg["playerId"] = newPlayer.id;
    msg["totalPlayers"] = (int) players.size();
    sendJSON(clientAddr, msg);

    if ((int) players.size() == MAX_PLAYERS) {
        startGame();
    }
}

void checkGameEnd() {
    if (isWordComplete(currentState)) {
        gameOver = true;
        json msg;
        msg["type"] = "gameOver";
        msg["won"] = true;
        msg["word"] = secretWord;
        broadcast(msg);
        std::cout << "Fim de jogo: vitoria!" << std::endl;
    } else if (errorCount >= MAX_ERRORS) {
        gameOver = true;
        json msg;
        msg["type"] = "gameOver";
        msg["won"] = false;
        msg["word"] = secretWord;
        broadcast(msg);
        std::cout << "Fim de jogo: derrota!" << std::endl;
    }
}

void handleGuess(const sockaddr_in &clientAddr, const json &data) {
    if (!gameStarted || gameOver) {
        sendErrorTo(clientAddr, "O jogo ainda nao comecou ou ja terminou");
        return;
    }

    int playerIndex = findPlayerByAddr(clientAddr);
    if (playerIndex == -1) {
        sendErrorTo(clientAddr, "Jogador nao reconhecido, envie join primeiro");
        return;
    }

    if (!data.contains("letter") || !data["letter"].is_string()) {
        sendErrorTo(clientAddr, "Mensagem de tentativa invalida");
        return;
    }

    std::string letterStr = data["letter"].get<std::string>();
    if (letterStr.size() != 1 || !isalpha((unsigned char) letterStr[0])) {
        sendErrorTo(clientAddr, "Digite apenas uma letra (a-z)");
        return;
    }

    char letter = (char) tolower((unsigned char) letterStr[0]);

    if (triedLetters.find(letter) != triedLetters.end()) {
        sendErrorTo(clientAddr, "Essa letra ja foi tentada");
        return;
    }

    triedLetters.insert(letter);
    int playerId = players[playerIndex].id;
    bool found = tryLetter(secretWord, letter, currentState);
    if (!found) {
        errorCount++;
    }

    json msg;
    msg["type"] = "update";
    msg["state"] = stateToString(currentState);
    msg["errorCount"] = errorCount;
    msg["triedLetters"] = triedLettersToJson();
    msg["lastPlayer"] = playerId;
    msg["letter"] = std::string(1, letter);
    msg["correct"] = found;
    broadcast(msg);

    checkGameEnd();
}

void handleMessage(const sockaddr_in &clientAddr, const std::string &raw) {
    json data;
    try {
        data = json::parse(raw);
    } catch (const std::exception &e) {
        std::cerr << "Mensagem invalida recebida: " << e.what() << std::endl;
        return;
    }

    if (!data.contains("type") || !data["type"].is_string()) {
        return;
    }

    std::string type = data["type"].get<std::string>();

    if (type == "join") {
        handleJoin(clientAddr);
    } else if (type == "guess") {
        handleGuess(clientAddr, data);
    }
}

int main() {
    srand((unsigned int) time(NULL));

    sockUDP = socket(AF_INET, SOCK_DGRAM, 0);
    if (sockUDP < 0) {
        perror("Erro ao criar socket UDP");
        return 1;
    }

    sockaddr_in serverAddr;
    memset(&serverAddr, 0, sizeof(serverAddr));
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_addr.s_addr = INADDR_ANY;
    serverAddr.sin_port = htons(UDP_PORT);

    if (bind(sockUDP, (struct sockaddr *) &serverAddr, sizeof(serverAddr)) < 0) {
        perror("Erro ao associar socket UDP");
        close(sockUDP);
        return 1;
    }

    std::cout << "Servidor da forca multiplayer rodando na porta " << UDP_PORT << std::endl;
    std::cout << "Aguardando ate " << MAX_PLAYERS << " jogadores..." << std::endl;

    char buffer[MAX_BUFFER_SIZE];

    while (true) {
        sockaddr_in clientAddr;
        socklen_t clientLen = sizeof(clientAddr);

        int recvLen = recvfrom(sockUDP, buffer, MAX_BUFFER_SIZE - 1, 0,
                                (struct sockaddr *) &clientAddr, &clientLen);

        if (recvLen > 0) {
            buffer[recvLen] = '\0';
            handleMessage(clientAddr, std::string(buffer));
        } else if (recvLen < 0) {
            perror("Erro ao receber dados via UDP");
        }
    }

    close(sockUDP);
    return 0;
}