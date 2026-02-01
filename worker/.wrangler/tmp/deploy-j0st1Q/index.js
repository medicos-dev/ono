var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// src/uno-logic.ts
function createStandardDeck() {
  const deck = [];
  const colors = ["red" /* red */, "blue" /* blue */, "green" /* green */, "yellow" /* yellow */];
  for (const color of colors) {
    deck.push({ color, type: "number" /* number */, number: 0, isWild: false, isAction: false });
    for (let i = 1; i <= 9; i++) {
      deck.push({ color, type: "number" /* number */, number: i, isWild: false, isAction: false });
      deck.push({ color, type: "number" /* number */, number: i, isWild: false, isAction: false });
    }
    deck.push({ color, type: "skip" /* skip */, isWild: false, isAction: true });
    deck.push({ color, type: "skip" /* skip */, isWild: false, isAction: true });
    deck.push({ color, type: "reverse" /* reverse */, isWild: false, isAction: true });
    deck.push({ color, type: "reverse" /* reverse */, isWild: false, isAction: true });
    deck.push({ color, type: "drawTwo" /* drawTwo */, isWild: false, isAction: true });
    deck.push({ color, type: "drawTwo" /* drawTwo */, isWild: false, isAction: true });
  }
  for (let i = 0; i < 4; i++) {
    deck.push({ color: "wild" /* wild */, type: "wild" /* wild */, isWild: true, isAction: true });
    deck.push({ color: "wild" /* wild */, type: "wildDrawFour" /* wildDrawFour */, isWild: true, isAction: true });
  }
  return deck;
}
__name(createStandardDeck, "createStandardDeck");
function shuffleDeck(deck) {
  const shuffled = [...deck];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  return shuffled;
}
__name(shuffleDeck, "shuffleDeck");
function dealCards(deck, playerCount) {
  const hands = [];
  const cardsPerPlayer = 7;
  for (let i = 0; i < playerCount; i++) {
    hands.push([]);
  }
  for (let i = 0; i < cardsPerPlayer; i++) {
    for (let j = 0; j < playerCount; j++) {
      if (deck.length > 0) {
        hands[j].push(deck.shift());
      }
    }
  }
  return hands;
}
__name(dealCards, "dealCards");
function canPlayCard(card, topCard, activeColor, pendingDrawCount, playerHand) {
  if (card.isWild) {
    if (card.type === "wildDrawFour" /* wildDrawFour */) {
      if (playerHand && playerHand.length > 0) {
        const hasMatchingColor = playerHand.some(
          (c) => !c.isWild && c.color === activeColor
        );
        if (hasMatchingColor) {
          return false;
        }
      }
      if (pendingDrawCount > 0 && pendingDrawCount < 8) {
        return false;
      }
      if (pendingDrawCount >= 8) {
        return true;
      }
      return true;
    }
    return true;
  }
  if (card.color === activeColor) {
    return true;
  }
  if (topCard.isWild) {
    return card.color === activeColor;
  }
  if (card.type === topCard.type) {
    return true;
  }
  if (card.type === "number" /* number */ && topCard.type === "number" /* number */ && card.number === topCard.number) {
    return true;
  }
  if (pendingDrawCount > 0) {
    if (pendingDrawCount % 2 === 0 && card.type === "drawTwo" /* drawTwo */ && card.color === activeColor) {
      return true;
    }
    if (pendingDrawCount >= 8 && card.type === "wildDrawFour" /* wildDrawFour */) {
      return true;
    }
  }
  return false;
}
__name(canPlayCard, "canPlayCard");
function processCardPlay(gameState, card, chosenColor, playerId, playerIds) {
  let newActiveColor = gameState.activeColor;
  let newDirection = gameState.direction;
  let newPendingDrawCount = gameState.pendingDrawCount;
  let newCurrentTurnPlayerId = playerId;
  const newDiscardPile = [...gameState.discardPile, card];
  if (card.isWild) {
    if (chosenColor) {
      newActiveColor = chosenColor;
    } else {
      newActiveColor = "red" /* red */;
    }
  } else {
    newActiveColor = card.color;
  }
  if (card.type === "skip" /* skip */) {
    newCurrentTurnPlayerId = getNextPlayer(playerId, playerIds, newDirection);
    newCurrentTurnPlayerId = getNextPlayer(newCurrentTurnPlayerId, playerIds, newDirection);
  } else if (card.type === "reverse" /* reverse */) {
    newDirection *= -1;
    if (playerIds.length === 2) {
      newCurrentTurnPlayerId = getNextPlayer(playerId, playerIds, newDirection);
    }
  } else if (card.type === "drawTwo" /* drawTwo */) {
    if (newPendingDrawCount > 0 && newPendingDrawCount % 2 === 0) {
      newPendingDrawCount += 2;
    } else {
      newPendingDrawCount = 2;
    }
    newCurrentTurnPlayerId = getNextPlayer(playerId, playerIds, newDirection);
  } else if (card.type === "wildDrawFour" /* wildDrawFour */) {
    if (newPendingDrawCount >= 8) {
      newPendingDrawCount += 4;
    } else {
      newPendingDrawCount = 4;
    }
    newCurrentTurnPlayerId = getNextPlayer(playerId, playerIds, newDirection);
  } else {
    newCurrentTurnPlayerId = getNextPlayer(playerId, playerIds, newDirection);
  }
  if (card.type !== "drawTwo" /* drawTwo */ && card.type !== "wildDrawFour" /* wildDrawFour */) {
    newPendingDrawCount = 0;
  }
  const animationId = `${playerId}|${JSON.stringify(card)}|${Date.now()}`;
  return {
    ...gameState,
    discardPile: newDiscardPile,
    activeColor: newActiveColor,
    direction: newDirection,
    pendingDrawCount: newPendingDrawCount,
    currentTurnPlayerId: newCurrentTurnPlayerId,
    lastPlayedCardJson: JSON.stringify(card),
    pendingWildColorChoice: card.isWild && chosenColor ? chosenColor : null,
    lastPlayedCardAnimationId: animationId,
    stateVersion: gameState.stateVersion + 1,
    lastActivity: (/* @__PURE__ */ new Date()).toISOString()
  };
}
__name(processCardPlay, "processCardPlay");
function getNextPlayer(currentPlayerId, playerIds, direction, playersWithSeats) {
  if (playersWithSeats && playersWithSeats.length > 0) {
    const currentPlayer = playersWithSeats.find((p) => p.id === currentPlayerId);
    if (!currentPlayer) {
      return playerIds[0];
    }
    const sortedPlayers = [...playersWithSeats].sort((a, b) => {
      const seatA = a.seatNumber ?? 999;
      const seatB = b.seatNumber ?? 999;
      return seatA - seatB;
    });
    const currentIndex2 = sortedPlayers.findIndex((p) => p.id === currentPlayerId);
    if (currentIndex2 === -1) {
      return sortedPlayers[0].id;
    }
    let nextIndex2 = currentIndex2 + direction;
    if (nextIndex2 < 0) {
      nextIndex2 = sortedPlayers.length - 1;
    } else if (nextIndex2 >= sortedPlayers.length) {
      nextIndex2 = 0;
    }
    return sortedPlayers[nextIndex2].id;
  }
  const currentIndex = playerIds.indexOf(currentPlayerId);
  if (currentIndex === -1) {
    return playerIds[0];
  }
  let nextIndex = currentIndex + direction;
  if (nextIndex < 0) {
    nextIndex = playerIds.length - 1;
  } else if (nextIndex >= playerIds.length) {
    nextIndex = 0;
  }
  return playerIds[nextIndex];
}
__name(getNextPlayer, "getNextPlayer");
async function checkUnoCall(gameState, playerId, handSize, env, roomCode) {
  const playerIds = Object.keys(gameState.unoCalled);
  for (const pid of playerIds) {
    if (pid !== playerId && gameState.unoCalled[pid] === true) {
      const lastCardPlayTime = new Date(gameState.lastActivity).getTime();
      const now = (/* @__PURE__ */ new Date()).getTime();
      if (now - lastCardPlayTime > 2e3) {
        continue;
      }
      const playerResult = await env.DB.prepare("SELECT * FROM players WHERE id = ? AND room_code = ?").bind(pid, roomCode).first();
      const player = playerResult;
      if (player) {
        const hand = JSON.parse(player.hand_json);
        if (hand.length !== 1 && gameState.unoCalled[pid]) {
          const penalty = hand.concat(gameState.drawPile.splice(0, 2));
          await env.DB.prepare("UPDATE players SET hand_json = ?, card_count = ? WHERE id = ?").bind(JSON.stringify(penalty), penalty.length, pid).run();
          gameState.unoCalled[pid] = false;
          gameState.drawPile = gameState.drawPile;
        }
      }
    }
  }
  if (handSize === 1 && !gameState.unoCalled[playerId]) {
    setTimeout(async () => {
      const playerResult = await env.DB.prepare("SELECT * FROM players WHERE id = ? AND room_code = ?").bind(playerId, roomCode).first();
      const player = playerResult;
      if (player) {
        const hand = JSON.parse(player.hand_json);
        if (hand.length === 1 && !gameState.unoCalled[playerId]) {
          const penalty = hand.concat(gameState.drawPile.splice(0, 2));
          env.DB.prepare("UPDATE players SET hand_json = ?, card_count = ? WHERE id = ?").bind(JSON.stringify(penalty), penalty.length, playerId).run();
        }
      }
    }, 2e3);
  }
}
__name(checkUnoCall, "checkUnoCall");

// src/index.ts
var index_default = {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;
    try {
      if (path === "/" && method === "GET") {
        return new Response(
          JSON.stringify({
            service: "ONO Game API",
            status: "online",
            version: "1.0.0",
            endpoints: {
              room: {
                create: "POST /room/create",
                join: "POST /room/join",
                leave: "POST /room/leave",
                delete: "DELETE /room/{code}",
                resignHost: "POST /room/resign-host"
              },
              game: {
                start: "POST /game/start",
                play: "POST /game/play",
                draw: "POST /game/draw",
                uno: "POST /game/uno",
                pass: "POST /game/pass"
              },
              sync: {
                sync: "POST /sync",
                poll: "GET /poll/{code}",
                heartbeat: "POST /heartbeat"
              }
            }
          }),
          {
            status: 200,
            headers: { "Content-Type": "application/json" }
          }
        );
      } else if (path === "/room/create" && method === "POST") {
        return handleCreateRoom(request, env);
      } else if (path === "/room/join" && method === "POST") {
        return handleJoinRoom(request, env);
      } else if (path === "/room/leave" && method === "POST") {
        return handleLeaveRoom(request, env);
      } else if (path.startsWith("/room/") && method === "DELETE") {
        const code = path.split("/")[2];
        return handleDeleteRoom(code, env);
      } else if (path === "/room/resign-host" && method === "POST") {
        return handleResignHost(request, env);
      } else if (path === "/game/start" && method === "POST") {
        return handleStartGame(request, env);
      } else if (path === "/game/play" && method === "POST") {
        return handlePlayCard(request, env);
      } else if (path === "/game/draw" && method === "POST") {
        return handleDrawCard(request, env);
      } else if (path === "/game/uno" && method === "POST") {
        return handleCallUno(request, env);
      } else if (path === "/game/pass" && method === "POST") {
        return handlePassTurn(request, env);
      } else if (path === "/sync" && method === "POST") {
        return handleSync(request, env);
      } else if (path.startsWith("/poll/") && method === "GET") {
        const code = path.split("/")[2];
        return handlePoll(code, url.searchParams, env);
      } else if (path === "/heartbeat" && method === "POST") {
        return handleHeartbeat(request, env);
      } else if (path === "/rtc/signal" && method === "POST") {
        return handleSendRTCSignal(request, env);
      } else if (path.startsWith("/rtc/signals/") && method === "GET") {
        const playerId = path.split("/")[3];
        return handleGetRTCSignals(playerId, env);
      } else {
        return new Response("Not Found", { status: 404 });
      }
    } catch (error) {
      console.error("Error:", error);
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" }
      });
    }
  },
  async scheduled(_event, env) {
    await cleanupInactiveRooms(env);
  }
};
async function handleCreateRoom(request, env) {
  try {
    const body = await request.json();
    const { playerName, playerId, roomCode: requestedRoomCode } = body;
    if (!playerName || !playerId) {
      return new Response(JSON.stringify({ error: "Missing playerName or playerId" }), {
        status: 400,
        headers: { "Content-Type": "application/json" }
      });
    }
    if (!requestedRoomCode || requestedRoomCode.trim().length === 0) {
      return new Response(JSON.stringify({ error: "Room code is required" }), {
        status: 400,
        headers: { "Content-Type": "application/json" }
      });
    }
    const roomCode = requestedRoomCode.trim().toUpperCase();
    if (!/^[A-Z0-9]{3,10}$/.test(roomCode)) {
      return new Response(JSON.stringify({ error: "Room code must be 3-10 alphanumeric characters" }), {
        status: 400,
        headers: { "Content-Type": "application/json" }
      });
    }
    const existingRow = await env.DB.prepare("SELECT code FROM rooms WHERE code = ?").bind(roomCode).first();
    if (existingRow) {
      return new Response(JSON.stringify({ error: "Room code already exists. Please choose a different code." }), {
        status: 400,
        headers: { "Content-Type": "application/json" }
      });
    }
    const now = (/* @__PURE__ */ new Date()).toISOString();
    const gameState = {
      drawPile: [],
      discardPile: [],
      activeColor: "red" /* red */,
      currentTurnPlayerId: null,
      direction: 1,
      pendingDrawCount: 0,
      lastPlayedCardJson: null,
      pendingWildColorChoice: null,
      unoCalled: {},
      stateVersion: 0,
      lastActivity: now
    };
    await env.DB.prepare(
      `INSERT INTO rooms (code, host_id, status, game_state_json, current_turn_player_id, direction, active_color, pending_draw_count, state_version, last_activity)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(
      roomCode,
      playerId,
      "lobby" /* lobby */,
      JSON.stringify(gameState),
      null,
      1,
      "red" /* red */,
      0,
      0,
      now
    ).run();
    await env.DB.prepare(
      `INSERT INTO players (id, room_code, name, is_host, seat_number, hand_json, card_count, last_seen)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(
      playerId,
      roomCode,
      playerName,
      true,
      1,
      JSON.stringify([]),
      0,
      now
    ).run();
    const room = await getRoomWithPlayers(roomCode, env);
    if (!room) {
      return new Response(JSON.stringify({
        type: "ROOM_DELETED",
        reason: "NOT_FOUND",
        events: [createEvent("ROOM_DELETED" /* ROOM_DELETED */, playerId, { reason: "NOT_FOUND" })]
      }), {
        status: 404,
        headers: { "Content-Type": "application/json" }
      });
    }
    return new Response(JSON.stringify(room), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: "Failed to create room" }), {
      status: 500,
      headers: { "Content-Type": "application/json" }
    });
  }
}
__name(handleCreateRoom, "handleCreateRoom");
async function handleJoinRoom(request, env) {
  try {
    const body = await request.json();
    const { roomCode, playerName, playerId } = body;
    if (!roomCode || !playerName || !playerId) {
      return new Response(JSON.stringify({ error: "Missing required fields" }), {
        status: 400,
        headers: { "Content-Type": "application/json" }
      });
    }
    const code = roomCode.toUpperCase();
    const now = (/* @__PURE__ */ new Date()).toISOString();
    const roomRow = await env.DB.prepare("SELECT code, state_version FROM rooms WHERE code = ?").bind(code).first();
    if (!roomRow) {
      return new Response(JSON.stringify({ error: "ROOM_NOT_FOUND" }), {
        status: 404,
        headers: { "Content-Type": "application/json" }
      });
    }
    const existingPlayer = await env.DB.prepare("SELECT id FROM players WHERE id = ? AND room_code = ?").bind(playerId, code).first();
    if (!existingPlayer) {
      try {
        await env.DB.prepare(
          `INSERT INTO players (id, room_code, name, is_host, is_spectator, seat_number, hand_json, card_count, last_seen)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
        ).bind(
          playerId,
          code,
          playerName,
          false,
          0,
          null,
          JSON.stringify([]),
          0,
          now
        ).run();
      } catch (insertError) {
        const raceCheck = await env.DB.prepare("SELECT id FROM players WHERE id = ? AND room_code = ?").bind(playerId, code).first();
        if (!raceCheck) {
          throw new Error(`Failed to insert player: ${insertError.message}`);
        }
      }
    } else {
      await env.DB.prepare("UPDATE players SET last_seen = ?, name = ? WHERE id = ? AND room_code = ?").bind(now, playerName, playerId, code).run();
    }
    await env.DB.prepare("UPDATE rooms SET state_version = state_version + 1, last_activity = ? WHERE code = ?").bind(now, code).run();
    const room = await getRoomWithPlayers(code, env);
    if (!room) {
      return new Response(JSON.stringify({ error: "ROOM_NOT_FOUND" }), {
        status: 404,
        headers: { "Content-Type": "application/json" }
      });
    }
    return new Response(JSON.stringify(room), {
      headers: { "Content-Type": "application/json" }
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: "INTERNAL_ERROR" }), {
      status: 500,
      headers: { "Content-Type": "application/json" }
    });
  }
}
__name(handleJoinRoom, "handleJoinRoom");
async function handleLeaveRoom(request, env) {
  try {
    const body = await request.json();
    const { roomCode, playerId } = body;
    const code = roomCode.toUpperCase();
    const player = await env.DB.prepare("SELECT * FROM players WHERE id = ? AND room_code = ?").bind(playerId, code).first();
    if (!player) {
      return new Response(JSON.stringify({ error: "Player not found" }), {
        status: 404,
        headers: { "Content-Type": "application/json" }
      });
    }
    if (player.is_host) {
      await env.DB.prepare("DELETE FROM players WHERE room_code = ?").bind(code).run();
      await env.DB.prepare("DELETE FROM rooms WHERE code = ?").bind(code).run();
      return new Response(JSON.stringify({
        type: "ROOM_DELETED",
        reason: "HOST_LEFT",
        events: [createEvent("ROOM_DELETED" /* ROOM_DELETED */, playerId, { reason: "HOST_LEFT" })]
      }), {
        headers: { "Content-Type": "application/json" }
      });
    }
    await env.DB.prepare("DELETE FROM players WHERE id = ? AND room_code = ?").bind(playerId, code).run();
    const remainingPlayers = await env.DB.prepare("SELECT COUNT(*) as count FROM players WHERE room_code = ?").bind(code).first();
    if (remainingPlayers && remainingPlayers.count === 0) {
      await env.DB.prepare("DELETE FROM rooms WHERE code = ?").bind(code).run();
      return new Response(JSON.stringify({
        type: "ROOM_DELETED",
        reason: "NO_PLAYERS",
        events: [createEvent("ROOM_DELETED" /* ROOM_DELETED */, playerId, { reason: "NO_PLAYERS" })]
      }), {
        headers: { "Content-Type": "application/json" }
      });
    }
    await incrementRoomStateVersion(code, env);
    const updatedRoom = await getRoomWithPlayers(code, env);
    if (!updatedRoom) {
      return new Response(JSON.stringify({
        type: "ROOM_DELETED",
        reason: "NOT_FOUND",
        events: [createEvent("ROOM_DELETED" /* ROOM_DELETED */, playerId, { reason: "NOT_FOUND" })]
      }), {
        headers: { "Content-Type": "application/json" }
      });
    }
    updatedRoom.events = [createEvent("PLAYER_LEFT" /* PLAYER_LEFT */, playerId, { playerName: player.name })];
    return new Response(JSON.stringify(updatedRoom), {
      headers: { "Content-Type": "application/json" }
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: "INTERNAL_ERROR" }), {
      status: 500,
      headers: { "Content-Type": "application/json" }
    });
  }
}
__name(handleLeaveRoom, "handleLeaveRoom");
async function handleDeleteRoom(code, env) {
  await env.DB.prepare("DELETE FROM players WHERE room_code = ?").bind(code.toUpperCase()).run();
  await env.DB.prepare("DELETE FROM rooms WHERE code = ?").bind(code.toUpperCase()).run();
  return new Response(JSON.stringify({ success: true }), {
    headers: { "Content-Type": "application/json" }
  });
}
__name(handleDeleteRoom, "handleDeleteRoom");
async function handleResignHost(request, env) {
  const body = await request.json();
  const { roomCode, playerId } = body;
  const room = await env.DB.prepare("SELECT * FROM rooms WHERE code = ?").bind(roomCode.toUpperCase()).first();
  if (!room || room.host_id !== playerId) {
    return new Response(JSON.stringify({ error: "Not the host" }), {
      status: 403,
      headers: { "Content-Type": "application/json" }
    });
  }
  const players = await env.DB.prepare("SELECT * FROM players WHERE room_code = ? AND id != ?").bind(roomCode.toUpperCase(), playerId).all();
  if (players.results.length === 0) {
    return new Response(JSON.stringify({ error: "No other players" }), {
      status: 400,
      headers: { "Content-Type": "application/json" }
    });
  }
  const randomPlayer = players.results[Math.floor(Math.random() * players.results.length)];
  await env.DB.prepare("UPDATE rooms SET host_id = ? WHERE code = ?").bind(randomPlayer.id, roomCode.toUpperCase()).run();
  await env.DB.prepare("UPDATE players SET is_host = ? WHERE id = ?").bind(false, playerId).run();
  await env.DB.prepare("UPDATE players SET is_host = ? WHERE id = ?").bind(true, randomPlayer.id).run();
  await incrementRoomStateVersion(roomCode.toUpperCase(), env);
  const updatedRoom = await getRoomWithPlayers(roomCode.toUpperCase(), env);
  if (!updatedRoom) {
    return new Response(JSON.stringify({
      type: "ROOM_DELETED",
      reason: "NOT_FOUND",
      events: [createEvent("ROOM_DELETED" /* ROOM_DELETED */, playerId, { reason: "NOT_FOUND" })]
    }), {
      headers: { "Content-Type": "application/json" }
    });
  }
  updatedRoom.events = [createEvent("HOST_CHANGED" /* HOST_CHANGED */, randomPlayer.id, {
    oldHostId: playerId,
    newHostId: randomPlayer.id,
    newHostName: randomPlayer.name
  })];
  return new Response(JSON.stringify(updatedRoom), {
    headers: { "Content-Type": "application/json" }
  });
}
__name(handleResignHost, "handleResignHost");
async function handleStartGame(request, env) {
  const body = await request.json();
  const { roomCode, playerId } = body;
  const roomData = await env.DB.prepare("SELECT * FROM rooms WHERE code = ?").bind(roomCode.toUpperCase()).first();
  if (!roomData || roomData.host_id !== playerId) {
    return new Response(JSON.stringify({ error: "Not the host" }), {
      status: 403,
      headers: { "Content-Type": "application/json" }
    });
  }
  const playersData = await env.DB.prepare("SELECT * FROM players WHERE room_code = ? AND (is_spectator = 0 OR is_spectator IS NULL) ORDER BY COALESCE(seat_number, 999), is_host DESC, name ASC").bind(roomCode.toUpperCase()).all();
  const activePlayers = playersData.results.filter((p) => !p.is_spectator || p.is_spectator === 0);
  if (activePlayers.length < 2) {
    return new Response(JSON.stringify({ error: "Need at least 2 players" }), {
      status: 400,
      headers: { "Content-Type": "application/json" }
    });
  }
  const deck = shuffleDeck(createStandardDeck());
  const hands = dealCards(deck, activePlayers.length);
  for (let i = 0; i < activePlayers.length; i++) {
    const player = activePlayers[i];
    await env.DB.prepare("UPDATE players SET hand_json = ?, card_count = ? WHERE id = ?").bind(
      JSON.stringify(hands[i]),
      hands[i].length,
      player.id
    ).run();
  }
  const hostPlayer = activePlayers[0];
  const playerIdsOrdered = await getPlayerIds(roomCode.toUpperCase(), env);
  const newStateVersion = roomData.state_version + 1;
  const initialGameState = {
    drawPile: deck,
    discardPile: [],
    activeColor: "red" /* red */,
    currentTurnPlayerId: hostPlayer.id,
    direction: 1,
    pendingDrawCount: 0,
    lastPlayedCardJson: null,
    pendingWildColorChoice: null,
    unoCalled: {},
    stateVersion: newStateVersion,
    lastActivity: (/* @__PURE__ */ new Date()).toISOString(),
    winnerPlayerId: null,
    winnerTimestamp: null,
    lastPlayedCardAnimationId: null
  };
  await env.DB.prepare(
    `UPDATE rooms SET status = ?, game_state_json = ?, current_turn_player_id = ?, direction = ?, active_color = ?, pending_draw_count = ?, state_version = ?, last_activity = ?
     WHERE code = ?`
  ).bind(
    "playing" /* playing */,
    JSON.stringify(initialGameState),
    initialGameState.currentTurnPlayerId,
    initialGameState.direction,
    initialGameState.activeColor,
    initialGameState.pendingDrawCount,
    newStateVersion,
    initialGameState.lastActivity,
    roomCode.toUpperCase()
  ).run();
  const room = await getRoomWithPlayers(roomCode.toUpperCase(), env);
  if (!room) {
    return new Response(JSON.stringify({
      type: "ROOM_DELETED",
      reason: "NOT_FOUND",
      events: [createEvent("ROOM_DELETED" /* ROOM_DELETED */, playerId, { reason: "NOT_FOUND" })]
    }), {
      headers: { "Content-Type": "application/json" }
    });
  }
  return new Response(JSON.stringify(room), {
    headers: { "Content-Type": "application/json" }
  });
}
__name(handleStartGame, "handleStartGame");
async function handlePlayCard(request, env) {
  const body = await request.json();
  const { roomCode, playerId, card, chosenColor } = body;
  const roomData = await env.DB.prepare("SELECT * FROM rooms WHERE code = ?").bind(roomCode.toUpperCase()).first();
  if (!roomData) {
    return new Response(JSON.stringify({ error: "Room not found" }), {
      status: 404,
      headers: { "Content-Type": "application/json" }
    });
  }
  if (roomData.current_turn_player_id !== playerId) {
    return new Response(JSON.stringify({ error: "Not your turn" }), {
      status: 403,
      headers: { "Content-Type": "application/json" }
    });
  }
  const gameState = JSON.parse(roomData.game_state_json);
  const player = await env.DB.prepare("SELECT * FROM players WHERE id = ? AND room_code = ?").bind(playerId, roomCode.toUpperCase()).first();
  if (!player) {
    return new Response(JSON.stringify({ error: "Player not found" }), {
      status: 404,
      headers: { "Content-Type": "application/json" }
    });
  }
  const hand = JSON.parse(player.hand_json);
  const cardIndex = hand.findIndex(
    (c) => c.color === card.color && c.type === card.type && c.number === card.number
  );
  if (cardIndex === -1) {
    return new Response(JSON.stringify({ error: "Card not in hand" }), {
      status: 400,
      headers: { "Content-Type": "application/json" }
    });
  }
  const playerData = await env.DB.prepare("SELECT * FROM players WHERE id = ? AND room_code = ?").bind(playerId, roomCode.toUpperCase()).first();
  if (playerData && playerData.is_spectator) {
    return new Response(JSON.stringify({ error: "Spectators cannot play cards" }), {
      status: 403,
      headers: { "Content-Type": "application/json" }
    });
  }
  const topCard = gameState.discardPile.length > 0 ? gameState.discardPile[gameState.discardPile.length - 1] : null;
  if (topCard != null && !canPlayCard(card, topCard, gameState.activeColor, gameState.pendingDrawCount, hand)) {
    return new Response(JSON.stringify({ error: "Invalid card" }), {
      status: 400,
      headers: { "Content-Type": "application/json" }
    });
  }
  if (card.isWild && !chosenColor) {
    return new Response(JSON.stringify({ error: "Wild card requires color choice" }), {
      status: 400,
      headers: { "Content-Type": "application/json" }
    });
  }
  hand.splice(cardIndex, 1);
  let updatedGameState = processCardPlay(
    gameState,
    card,
    chosenColor,
    playerId,
    await getPlayerIds(roomCode.toUpperCase(), env)
  );
  if (updatedGameState.discardPile.length > 6) {
    const pile = updatedGameState.discardPile;
    const lastCard = pile[pile.length - 1];
    const toRecycle = pile.slice(0, -1);
    const newDrawPile = shuffleDeck([...updatedGameState.drawPile, ...toRecycle]);
    updatedGameState = {
      ...updatedGameState,
      drawPile: newDrawPile,
      discardPile: [lastCard]
    };
  }
  let winnerDetected = false;
  let winnerPlayerId = null;
  if (hand.length === 0) {
    winnerDetected = true;
    winnerPlayerId = playerId;
    updatedGameState.winnerPlayerId = playerId;
    updatedGameState.winnerTimestamp = (/* @__PURE__ */ new Date()).toISOString();
    updatedGameState.currentTurnPlayerId = null;
  }
  await env.DB.prepare("UPDATE players SET hand_json = ?, card_count = ? WHERE id = ?").bind(JSON.stringify(hand), hand.length, playerId).run();
  await env.DB.prepare(
    `UPDATE rooms SET status = ?, game_state_json = ?, current_turn_player_id = ?, direction = ?, active_color = ?, pending_draw_count = ?, state_version = ?, last_activity = ?
     WHERE code = ?`
  ).bind(
    winnerDetected ? "finished" /* finished */ : "playing" /* playing */,
    JSON.stringify(updatedGameState),
    updatedGameState.currentTurnPlayerId,
    updatedGameState.direction,
    updatedGameState.activeColor,
    updatedGameState.pendingDrawCount,
    roomData.state_version + 1,
    updatedGameState.lastActivity,
    roomCode.toUpperCase()
  ).run();
  if (!winnerDetected) {
    await checkUnoCall(updatedGameState, playerId, hand.length, env, roomCode.toUpperCase());
  } else {
    setTimeout(async () => {
      await env.DB.prepare("DELETE FROM players WHERE room_code = ?").bind(roomCode.toUpperCase()).run();
      await env.DB.prepare("DELETE FROM rooms WHERE code = ?").bind(roomCode.toUpperCase()).run();
    }, 1e4);
  }
  const room = await getRoomWithPlayers(roomCode.toUpperCase(), env);
  if (!room) {
    return new Response(JSON.stringify({
      type: "ROOM_DELETED",
      reason: "NOT_FOUND",
      events: [createEvent("ROOM_DELETED" /* ROOM_DELETED */, playerId, { reason: "NOT_FOUND" })]
    }), {
      headers: { "Content-Type": "application/json" }
    });
  }
  return new Response(JSON.stringify(room), {
    headers: { "Content-Type": "application/json" }
  });
}
__name(handlePlayCard, "handlePlayCard");
async function handleDrawCard(request, env) {
  const body = await request.json();
  const { roomCode, playerId } = body;
  const roomData = await env.DB.prepare("SELECT * FROM rooms WHERE code = ?").bind(roomCode.toUpperCase()).first();
  if (!roomData || roomData.current_turn_player_id !== playerId) {
    return new Response(JSON.stringify({ error: "Not your turn" }), {
      status: 403,
      headers: { "Content-Type": "application/json" }
    });
  }
  const gameState = JSON.parse(roomData.game_state_json);
  const player = await env.DB.prepare("SELECT * FROM players WHERE id = ? AND room_code = ?").bind(playerId, roomCode.toUpperCase()).first();
  if (!player) {
    return new Response(JSON.stringify({ error: "Player not found" }), {
      status: 404,
      headers: { "Content-Type": "application/json" }
    });
  }
  let drawCount = 1;
  if (gameState.pendingDrawCount > 0) {
    drawCount = gameState.pendingDrawCount;
  }
  const hand = JSON.parse(player.hand_json);
  let drawPile = gameState.drawPile;
  if (drawPile.length < drawCount) {
    const discardPile = gameState.discardPile.slice(0, -1);
    drawPile = shuffleDeck(discardPile);
    gameState.discardPile = [gameState.discardPile[gameState.discardPile.length - 1]];
  }
  const drawnCards = drawPile.splice(0, drawCount);
  hand.push(...drawnCards);
  const updatedGameState = {
    ...gameState,
    drawPile,
    pendingDrawCount: 0,
    currentTurnPlayerId: getNextPlayer(
      playerId,
      await getPlayerIds(roomCode.toUpperCase(), env),
      gameState.direction
    ),
    stateVersion: roomData.state_version + 1,
    lastActivity: (/* @__PURE__ */ new Date()).toISOString()
  };
  await env.DB.prepare("UPDATE players SET hand_json = ?, card_count = ? WHERE id = ?").bind(JSON.stringify(hand), hand.length, playerId).run();
  await env.DB.prepare(
    `UPDATE rooms SET game_state_json = ?, current_turn_player_id = ?, pending_draw_count = ?, state_version = ?, last_activity = ?
     WHERE code = ?`
  ).bind(
    JSON.stringify(updatedGameState),
    updatedGameState.currentTurnPlayerId,
    0,
    updatedGameState.stateVersion,
    updatedGameState.lastActivity,
    roomCode.toUpperCase()
  ).run();
  const room = await getRoomWithPlayers(roomCode.toUpperCase(), env);
  if (!room) {
    return new Response(JSON.stringify({
      type: "ROOM_DELETED",
      reason: "NOT_FOUND",
      events: [createEvent("ROOM_DELETED" /* ROOM_DELETED */, playerId, { reason: "NOT_FOUND" })]
    }), {
      headers: { "Content-Type": "application/json" }
    });
  }
  return new Response(JSON.stringify(room), {
    headers: { "Content-Type": "application/json" }
  });
}
__name(handleDrawCard, "handleDrawCard");
async function handleCallUno(request, env) {
  const body = await request.json();
  const { roomCode, playerId } = body;
  const roomData = await env.DB.prepare("SELECT * FROM rooms WHERE code = ?").bind(roomCode.toUpperCase()).first();
  if (!roomData) {
    return new Response(JSON.stringify({ error: "Room not found" }), {
      status: 404,
      headers: { "Content-Type": "application/json" }
    });
  }
  const gameState = JSON.parse(roomData.game_state_json);
  const player = await env.DB.prepare("SELECT * FROM players WHERE id = ? AND room_code = ?").bind(playerId, roomCode.toUpperCase()).first();
  if (!player) {
    return new Response(JSON.stringify({ error: "Player not found" }), {
      status: 404,
      headers: { "Content-Type": "application/json" }
    });
  }
  const hand = JSON.parse(player.hand_json);
  if (hand.length !== 1) {
    return new Response(JSON.stringify({ error: "Must have exactly 1 card" }), {
      status: 400,
      headers: { "Content-Type": "application/json" }
    });
  }
  if (gameState.unoCalled[playerId]) {
    return new Response(JSON.stringify({ error: "UNO already called" }), {
      status: 400,
      headers: { "Content-Type": "application/json" }
    });
  }
  gameState.unoCalled[playerId] = true;
  gameState.stateVersion = roomData.state_version + 1;
  gameState.lastActivity = (/* @__PURE__ */ new Date()).toISOString();
  await env.DB.prepare("UPDATE rooms SET game_state_json = ?, state_version = ?, last_activity = ? WHERE code = ?").bind(JSON.stringify(gameState), gameState.stateVersion, gameState.lastActivity, roomCode.toUpperCase()).run();
  const room = await getRoomWithPlayers(roomCode.toUpperCase(), env);
  if (!room) {
    return new Response(JSON.stringify({
      type: "ROOM_DELETED",
      reason: "NOT_FOUND",
      events: [createEvent("ROOM_DELETED" /* ROOM_DELETED */, playerId, { reason: "NOT_FOUND" })]
    }), {
      headers: { "Content-Type": "application/json" }
    });
  }
  return new Response(JSON.stringify(room), {
    headers: { "Content-Type": "application/json" }
  });
}
__name(handleCallUno, "handleCallUno");
async function handlePassTurn(request, env) {
  const body = await request.json();
  const { roomCode, playerId } = body;
  const roomData = await env.DB.prepare("SELECT * FROM rooms WHERE code = ?").bind(roomCode.toUpperCase()).first();
  if (!roomData || roomData.current_turn_player_id !== playerId) {
    return new Response(JSON.stringify({ error: "Not your turn" }), {
      status: 403,
      headers: { "Content-Type": "application/json" }
    });
  }
  const gameState = JSON.parse(roomData.game_state_json);
  const updatedGameState = {
    ...gameState,
    currentTurnPlayerId: getNextPlayer(
      playerId,
      await getPlayerIds(roomCode.toUpperCase(), env),
      gameState.direction
    ),
    stateVersion: roomData.state_version + 1,
    lastActivity: (/* @__PURE__ */ new Date()).toISOString()
  };
  await env.DB.prepare(
    `UPDATE rooms SET game_state_json = ?, current_turn_player_id = ?, state_version = ?, last_activity = ?
     WHERE code = ?`
  ).bind(
    JSON.stringify(updatedGameState),
    updatedGameState.currentTurnPlayerId,
    updatedGameState.stateVersion,
    updatedGameState.lastActivity,
    roomCode.toUpperCase()
  ).run();
  const room = await getRoomWithPlayers(roomCode.toUpperCase(), env);
  if (!room) {
    return new Response(JSON.stringify({
      type: "ROOM_DELETED",
      reason: "NOT_FOUND",
      events: [createEvent("ROOM_DELETED" /* ROOM_DELETED */, playerId, { reason: "NOT_FOUND" })]
    }), {
      headers: { "Content-Type": "application/json" }
    });
  }
  return new Response(JSON.stringify(room), {
    headers: { "Content-Type": "application/json" }
  });
}
__name(handlePassTurn, "handlePassTurn");
async function handleSync(request, env) {
  const body = await request.json();
  const { roomCode, playerId, stateVersion } = body;
  const room = await getRoomWithPlayers(roomCode.toUpperCase(), env);
  if (!room) {
    return new Response(JSON.stringify({
      type: "ROOM_DELETED",
      reason: "NOT_FOUND",
      events: [createEvent("ROOM_DELETED" /* ROOM_DELETED */, playerId, { reason: "NOT_FOUND" })]
    }), {
      headers: { "Content-Type": "application/json" }
    });
  }
  if (room.gameState && room.gameState.stateVersion <= stateVersion) {
    return new Response(null, { status: 204 });
  }
  return new Response(JSON.stringify(room), {
    headers: { "Content-Type": "application/json" }
  });
}
__name(handleSync, "handleSync");
async function handlePoll(code, searchParams, env) {
  const playerId = searchParams.get("playerId");
  const lastKnownVersion = parseInt(searchParams.get("lastKnownVersion") || "0", 10);
  const isSpectator = searchParams.get("isSpectator") === "true";
  try {
    const roomStateVersion = await env.DB.prepare("SELECT state_version FROM rooms WHERE code = ?").bind(code.toUpperCase()).first();
    if (!roomStateVersion) {
      return new Response(JSON.stringify({
        type: "ROOM_DELETED",
        reason: "NOT_FOUND",
        events: [createEvent("ROOM_DELETED" /* ROOM_DELETED */, playerId || void 0, { reason: "NOT_FOUND" })]
      }), {
        headers: { "Content-Type": "application/json" }
      });
    }
    if (roomStateVersion.state_version > lastKnownVersion) {
      const room = await getRoomWithPlayers(code.toUpperCase(), env);
      if (room) {
        return new Response(JSON.stringify(room), {
          headers: { "Content-Type": "application/json" }
        });
      }
    }
    const maxWait = isSpectator ? 5 : 15;
    const checkInterval = isSpectator ? 2e3 : 1e3;
    for (let i = 0; i < maxWait; i++) {
      await new Promise((resolve) => setTimeout(resolve, checkInterval));
      try {
        const roomData = await env.DB.prepare("SELECT state_version FROM rooms WHERE code = ?").bind(code.toUpperCase()).first();
        if (!roomData) {
          return new Response(JSON.stringify({
            type: "ROOM_DELETED",
            reason: "NOT_FOUND",
            events: [createEvent("ROOM_DELETED" /* ROOM_DELETED */, playerId || void 0, { reason: "NOT_FOUND" })]
          }), {
            headers: { "Content-Type": "application/json" }
          });
        }
        if (roomData.state_version > lastKnownVersion) {
          const updatedRoom = await getRoomWithPlayers(code.toUpperCase(), env);
          if (updatedRoom) {
            return new Response(JSON.stringify(updatedRoom), {
              headers: { "Content-Type": "application/json" }
            });
          }
        }
      } catch (e) {
        return new Response(JSON.stringify({
          type: "ROOM_DELETED",
          reason: "NOT_FOUND",
          events: [createEvent("ROOM_DELETED" /* ROOM_DELETED */, playerId || void 0, { reason: "NOT_FOUND" })]
        }), {
          headers: { "Content-Type": "application/json" }
        });
      }
    }
    return new Response(JSON.stringify({ changed: false }), {
      status: 304,
      headers: { "Content-Type": "application/json" }
    });
  } catch (e) {
    return new Response(JSON.stringify({
      type: "ROOM_DELETED",
      reason: "NOT_FOUND",
      events: [createEvent("ROOM_DELETED" /* ROOM_DELETED */, playerId || void 0, { reason: "NOT_FOUND" })]
    }), {
      headers: { "Content-Type": "application/json" }
    });
  }
}
__name(handlePoll, "handlePoll");
async function handleHeartbeat(request, env) {
  const body = await request.json();
  const { roomCode, playerId } = body;
  await env.DB.prepare("UPDATE players SET last_seen = ? WHERE id = ? AND room_code = ?").bind((/* @__PURE__ */ new Date()).toISOString(), playerId, roomCode.toUpperCase()).run();
  return new Response(JSON.stringify({ success: true }), {
    headers: { "Content-Type": "application/json" }
  });
}
__name(handleHeartbeat, "handleHeartbeat");
async function cleanupInactiveRooms(env) {
  const cutoff = new Date(Date.now() - 5 * 60 * 1e3).toISOString();
  const staleRooms = await env.DB.prepare("SELECT code FROM rooms WHERE last_activity < ?").bind(cutoff).all();
  if (!staleRooms.results.length) return;
  const codes = staleRooms.results.map((r) => r.code);
  const placeholders = codes.map(() => "?").join(", ");
  await env.DB.prepare(
    `DELETE FROM players WHERE room_code IN (${placeholders})`
  ).bind(...codes).run();
  await env.DB.prepare(
    `DELETE FROM rooms WHERE code IN (${placeholders})`
  ).bind(...codes).run();
}
__name(cleanupInactiveRooms, "cleanupInactiveRooms");
async function getRoomWithPlayers(roomCode, env) {
  const roomData = await env.DB.prepare("SELECT * FROM rooms WHERE code = ?").bind(roomCode).first();
  if (!roomData) {
    return null;
  }
  const playerRows = await env.DB.prepare("SELECT * FROM players WHERE room_code = ? ORDER BY COALESCE(seat_number, 999), is_host DESC, name ASC").bind(roomCode).all();
  const players = playerRows.results.map((raw) => ({
    id: raw.id,
    name: raw.name,
    roomCode: raw.room_code,
    isHost: raw.is_host === 1,
    isSpectator: (raw.is_spectator ?? 0) === 1,
    seatNumber: raw.seat_number ?? void 0,
    hand: raw.hand_json ? JSON.parse(raw.hand_json) : [],
    lastSeen: raw.last_seen
  }));
  let gameState = null;
  if ((roomData.status === "playing" /* playing */ || roomData.status === "finished" /* finished */) && roomData.game_state_json) {
    try {
      gameState = JSON.parse(roomData.game_state_json);
    } catch {
      gameState = null;
    }
  }
  return {
    code: roomData.code,
    hostId: roomData.host_id,
    status: roomData.status,
    gameState,
    players,
    lastActivity: roomData.last_activity,
    stateVersion: roomData.state_version
  };
}
__name(getRoomWithPlayers, "getRoomWithPlayers");
async function getPlayerIds(roomCode, env) {
  const players = await env.DB.prepare("SELECT id, seat_number FROM players WHERE room_code = ? AND (is_spectator = 0 OR is_spectator IS NULL) ORDER BY COALESCE(seat_number, 999), is_host DESC, name ASC").bind(roomCode).all();
  return players.results.map((p) => p.id);
}
__name(getPlayerIds, "getPlayerIds");
async function incrementRoomStateVersion(roomCode, env) {
  const now = (/* @__PURE__ */ new Date()).toISOString();
  await env.DB.prepare("UPDATE rooms SET state_version = state_version + 1, last_activity = ? WHERE code = ?").bind(now, roomCode.toUpperCase()).run();
}
__name(incrementRoomStateVersion, "incrementRoomStateVersion");
function createEvent(type, playerId, data) {
  return {
    type,
    playerId,
    data,
    timestamp: (/* @__PURE__ */ new Date()).toISOString(),
    eventId: `${type}_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`
  };
}
__name(createEvent, "createEvent");
async function handleGetRTCSignals(playerId, env) {
  if (!playerId) {
    return new Response(JSON.stringify({ error: "Missing playerId" }), {
      status: 400,
      headers: { "Content-Type": "application/json" }
    });
  }
  const signals = await env.DB.prepare(
    "SELECT * FROM rtc_signals WHERE to_player_id = ? ORDER BY created_at ASC"
  ).bind(playerId).all();
  if (signals.results.length > 0) {
    const ids = signals.results.map((s) => s.id);
    const placeholders = ids.map(() => "?").join(",");
    await env.DB.prepare(`DELETE FROM rtc_signals WHERE id IN (${placeholders})`).bind(...ids).run();
  }
  return new Response(JSON.stringify({ signals: signals.results }), {
    headers: { "Content-Type": "application/json" }
  });
}
__name(handleGetRTCSignals, "handleGetRTCSignals");
async function handleSendRTCSignal(request, env) {
  try {
    const body = await request.json();
    const { roomCode, fromPlayerId, toPlayerId, signalType, signalData } = body;
    if (!roomCode || !fromPlayerId || !toPlayerId || !signalType || !signalData) {
      return new Response(JSON.stringify({ error: "Missing required fields" }), {
        status: 400,
        headers: { "Content-Type": "application/json" }
      });
    }
    await env.DB.prepare(
      `INSERT INTO rtc_signals (room_code, from_player_id, to_player_id, signal_type, signal_data)
       VALUES (?, ?, ?, ?, ?)`
    ).bind(roomCode.toUpperCase(), fromPlayerId, toPlayerId, signalType, signalData).run();
    return new Response(JSON.stringify({ success: true }), {
      headers: { "Content-Type": "application/json" }
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: "INTERNAL_ERROR" }), {
      status: 500,
      headers: { "Content-Type": "application/json" }
    });
  }
}
__name(handleSendRTCSignal, "handleSendRTCSignal");
export {
  index_default as default
};
//# sourceMappingURL=index.js.map
