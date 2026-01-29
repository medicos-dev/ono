import { createStandardDeck, shuffleDeck, dealCards, canPlayCard, processCardPlay, getNextPlayer, checkUnoCall } from './uno-logic';
import { Room, Player, GameState, RoomStatus, CardColor, GameEventType, GameEvent } from './types';

export interface Env {
  DB: D1Database;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    try {
      if (path === '/' && method === 'GET') {
        return new Response(
          JSON.stringify({
            service: 'ONO Game API',
            status: 'online',
            version: '1.0.0',
            endpoints: {
              room: {
                create: 'POST /room/create',
                join: 'POST /room/join',
                leave: 'POST /room/leave',
                delete: 'DELETE /room/{code}',
                resignHost: 'POST /room/resign-host',
              },
              game: {
                start: 'POST /game/start',
                play: 'POST /game/play',
                draw: 'POST /game/draw',
                uno: 'POST /game/uno',
                pass: 'POST /game/pass',
              },
              sync: {
                sync: 'POST /sync',
                poll: 'GET /poll/{code}',
                heartbeat: 'POST /heartbeat',
              },
            },
          }),
          {
            status: 200,
            headers: { 'Content-Type': 'application/json' },
          }
        );
      } else if (path === '/room/create' && method === 'POST') {
        return handleCreateRoom(request, env);
      } else if (path === '/room/join' && method === 'POST') {
        return handleJoinRoom(request, env);
      } else if (path === '/room/leave' && method === 'POST') {
        return handleLeaveRoom(request, env);
      } else if (path.startsWith('/room/') && method === 'DELETE') {
        const code = path.split('/')[2];
        return handleDeleteRoom(code, env);
      } else if (path === '/room/resign-host' && method === 'POST') {
        return handleResignHost(request, env);
      } else if (path === '/game/start' && method === 'POST') {
        return handleStartGame(request, env);
      } else if (path === '/game/play' && method === 'POST') {
        return handlePlayCard(request, env);
      } else if (path === '/game/draw' && method === 'POST') {
        return handleDrawCard(request, env);
      } else if (path === '/game/uno' && method === 'POST') {
        return handleCallUno(request, env);
      } else if (path === '/game/pass' && method === 'POST') {
        return handlePassTurn(request, env);
      } else if (path === '/sync' && method === 'POST') {
        return handleSync(request, env);
      } else if (path.startsWith('/poll/') && method === 'GET') {
        const code = path.split('/')[2];
        return handlePoll(code, url.searchParams, env);
      } else if (path === '/heartbeat' && method === 'POST') {
        return handleHeartbeat(request, env);
      } else if (path === '/rtc/signal' && method === 'POST') {
        return handleSendRTCSignal(request, env);
      } else if (path.startsWith('/rtc/signals/') && method === 'GET') {
        const playerId = path.split('/')[3];
        return handleGetRTCSignals(playerId, env);
      } else {
        return new Response('Not Found', { status: 404 });
      }
    } catch (error) {
      console.error('Error:', error);
      return new Response(JSON.stringify({ error: (error as Error).message }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }
  },

  async scheduled(_event: ScheduledEvent, env: Env): Promise<void> {
    await cleanupInactiveRooms(env);
  },
};

async function handleCreateRoom(request: Request, env: Env): Promise<Response> {
  const body = await request.json() as { playerName: string; playerId: string; roomCode?: string };
  const { playerName, playerId, roomCode: requestedRoomCode } = body;

  if (!playerName || !playerId) {
    return new Response(JSON.stringify({ error: 'Missing playerName or playerId' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Validate and use provided room code (must be provided and not empty)
  if (!requestedRoomCode || requestedRoomCode.trim().length === 0) {
    return new Response(JSON.stringify({ error: 'Room code is required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const roomCode = requestedRoomCode.trim().toUpperCase();

  // Validate room code format (alphanumeric, 3-10 characters)
  if (!/^[A-Z0-9]{3,10}$/.test(roomCode)) {
    return new Response(JSON.stringify({ error: 'Room code must be 3-10 alphanumeric characters' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Check if room already exists
  const existingRoom = await env.DB.prepare('SELECT * FROM rooms WHERE code = ?')
    .bind(roomCode)
    .first();

  if (existingRoom) {
    return new Response(JSON.stringify({ error: 'Room code already exists. Please choose a different code.' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }
  const now = new Date().toISOString();


  const gameState: GameState = {
    drawPile: [],
    discardPile: [],
    activeColor: CardColor.red,
    currentTurnPlayerId: null,
    direction: 1,
    pendingDrawCount: 0,
    lastPlayedCardJson: null,
    pendingWildColorChoice: null,
    unoCalled: {},
    stateVersion: 0,
    lastActivity: now,
  };

  const player: Player = {
    id: playerId,
    name: playerName,
    roomCode,
    isHost: true,
    hand: [],
    lastSeen: now,
  };

  await env.DB.prepare(
    `INSERT INTO rooms (code, host_id, status, game_state_json, current_turn_player_id, direction, active_color, pending_draw_count, state_version, last_activity)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  )
    .bind(
      roomCode,
      playerId,
      RoomStatus.lobby,
      JSON.stringify(gameState),
      null,
      1,
      CardColor.red,
      0,
      0,
      now,
    )
    .run();

  await env.DB.prepare(
    `INSERT INTO players (id, room_code, name, is_host, seat_number, hand_json, card_count, last_seen)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
  )
    .bind(
      playerId,
      roomCode,
      playerName,
      true,
      1,
      JSON.stringify([]),
      0,
      now,
    )
    .run();

  const room = await getRoomWithPlayers(roomCode, env);
  if (!room) {
    return new Response(JSON.stringify({
      type: 'ROOM_DELETED',
      reason: 'NOT_FOUND',
      events: [createEvent(GameEventType.ROOM_DELETED, playerId, { reason: 'NOT_FOUND' })],
    }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify(room), {
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handleJoinRoom(request: Request, env: Env): Promise<Response> {
  try {
    const body = await request.json() as { roomCode: string; playerName: string; playerId: string };
    const { roomCode, playerName, playerId } = body;

    if (!roomCode || !playerName || !playerId) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const code = roomCode.toUpperCase();
    const now = new Date().toISOString();

    const roomRow = await env.DB.prepare('SELECT code, state_version FROM rooms WHERE code = ?')
      .bind(code)
      .first<{ code: string; state_version: number }>();

    if (!roomRow) {
      return new Response(JSON.stringify({ error: 'ROOM_NOT_FOUND' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const existingPlayer = await env.DB.prepare('SELECT id FROM players WHERE id = ? AND room_code = ?')
      .bind(playerId, code)
      .first<{ id: string }>();

    if (!existingPlayer) {
      try {
        await env.DB.prepare(
          `INSERT INTO players (id, room_code, name, is_host, is_spectator, seat_number, hand_json, card_count, last_seen)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
        )
          .bind(
            playerId,
            code,
            playerName,
            false,
            0,
            null,
            JSON.stringify([]),
            0,
            now,
          )
          .run();
      } catch (insertError: any) {
        const raceCheck = await env.DB.prepare('SELECT id FROM players WHERE id = ? AND room_code = ?')
          .bind(playerId, code)
          .first<{ id: string }>();

        if (!raceCheck) {
          throw new Error(`Failed to insert player: ${insertError.message}`);
        }
      }
    } else {
      await env.DB.prepare('UPDATE players SET last_seen = ?, name = ? WHERE id = ? AND room_code = ?')
        .bind(now, playerName, playerId, code)
        .run();
    }

    // Always increment state version to ensure host gets the update
    await env.DB.prepare('UPDATE rooms SET state_version = state_version + 1, last_activity = ? WHERE code = ?')
      .bind(now, code)
      .run();

    const room = await getRoomWithPlayers(code, env);
    if (!room) {
      return new Response(JSON.stringify({ error: 'ROOM_NOT_FOUND' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify(room), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: 'INTERNAL_ERROR' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

async function handleLeaveRoom(request: Request, env: Env): Promise<Response> {
  try {
    const body = await request.json() as { roomCode: string; playerId: string };
    const { roomCode, playerId } = body;

    const code = roomCode.toUpperCase();

    const player = await env.DB.prepare('SELECT * FROM players WHERE id = ? AND room_code = ?')
      .bind(playerId, code)
      .first<{ is_host: boolean; name: string }>();

    if (!player) {
      return new Response(JSON.stringify({ error: 'Player not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    if (player.is_host) {

      await env.DB.prepare('DELETE FROM players WHERE room_code = ?')
        .bind(code)
        .run();
      await env.DB.prepare('DELETE FROM rooms WHERE code = ?')
        .bind(code)
        .run();

      // Explicit ROOM_DELETED response; never read room after deletion.
      return new Response(JSON.stringify({
        type: 'ROOM_DELETED',
        reason: 'HOST_LEFT',
        events: [createEvent(GameEventType.ROOM_DELETED, playerId, { reason: 'HOST_LEFT' })],
      }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }


    await env.DB.prepare('DELETE FROM players WHERE id = ? AND room_code = ?')
      .bind(playerId, code)
      .run();

    const remainingPlayers = await env.DB.prepare('SELECT COUNT(*) as count FROM players WHERE room_code = ?')
      .bind(code)
      .first<{ count: number }>();

    if (remainingPlayers && remainingPlayers.count === 0) {
      await env.DB.prepare('DELETE FROM rooms WHERE code = ?')
        .bind(code)
        .run();

      return new Response(JSON.stringify({
        type: 'ROOM_DELETED',
        reason: 'NO_PLAYERS',
        events: [createEvent(GameEventType.ROOM_DELETED, playerId, { reason: 'NO_PLAYERS' })],
      }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    await incrementRoomStateVersion(code, env);
    const updatedRoom = await getRoomWithPlayers(code, env);
    if (!updatedRoom) {
      return new Response(JSON.stringify({
        type: 'ROOM_DELETED',
        reason: 'NOT_FOUND',
        events: [createEvent(GameEventType.ROOM_DELETED, playerId, { reason: 'NOT_FOUND' })],
      }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }
    updatedRoom.events = [createEvent(GameEventType.PLAYER_LEFT, playerId, { playerName: player.name })];
    return new Response(JSON.stringify(updatedRoom), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (error) {

    return new Response(JSON.stringify({ error: 'INTERNAL_ERROR' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

async function handleDeleteRoom(code: string, env: Env): Promise<Response> {
  await env.DB.prepare('DELETE FROM players WHERE room_code = ?')
    .bind(code.toUpperCase())
    .run();
  await env.DB.prepare('DELETE FROM rooms WHERE code = ?')
    .bind(code.toUpperCase())
    .run();

  return new Response(JSON.stringify({ success: true }), {
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handleResignHost(request: Request, env: Env): Promise<Response> {
  const body = await request.json() as { roomCode: string; playerId: string };
  const { roomCode, playerId } = body;

  const room = await env.DB.prepare('SELECT * FROM rooms WHERE code = ?')
    .bind(roomCode.toUpperCase())
    .first<{ host_id: string }>();

  if (!room || room.host_id !== playerId) {
    return new Response(JSON.stringify({ error: 'Not the host' }), {
      status: 403,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const players = await env.DB.prepare('SELECT * FROM players WHERE room_code = ? AND id != ?')
    .bind(roomCode.toUpperCase(), playerId)
    .all<{ id: string; name: string }>();

  if (players.results.length === 0) {
    return new Response(JSON.stringify({ error: 'No other players' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const randomPlayer = players.results[Math.floor(Math.random() * players.results.length)];

  await env.DB.prepare('UPDATE rooms SET host_id = ? WHERE code = ?')
    .bind(randomPlayer.id, roomCode.toUpperCase())
    .run();

  await env.DB.prepare('UPDATE players SET is_host = ? WHERE id = ?')
    .bind(false, playerId)
    .run();

  await env.DB.prepare('UPDATE players SET is_host = ? WHERE id = ?')
    .bind(true, randomPlayer.id)
    .run();

  await incrementRoomStateVersion(roomCode.toUpperCase(), env);
  const updatedRoom = await getRoomWithPlayers(roomCode.toUpperCase(), env);
  if (!updatedRoom) {
    return new Response(JSON.stringify({
      type: 'ROOM_DELETED',
      reason: 'NOT_FOUND',
      events: [createEvent(GameEventType.ROOM_DELETED, playerId, { reason: 'NOT_FOUND' })],
    }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }
  updatedRoom.events = [createEvent(GameEventType.HOST_CHANGED, randomPlayer.id, {
    oldHostId: playerId,
    newHostId: randomPlayer.id,
    newHostName: randomPlayer.name,
  })];
  return new Response(JSON.stringify(updatedRoom), {
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handleStartGame(request: Request, env: Env): Promise<Response> {
  const body = await request.json() as { roomCode: string; playerId: string };
  const { roomCode, playerId } = body;

  const roomData = await env.DB.prepare('SELECT * FROM rooms WHERE code = ?')
    .bind(roomCode.toUpperCase())
    .first<{
      host_id: string;
      game_state_json: string;
      state_version: number;
    }>();

  if (!roomData || roomData.host_id !== playerId) {
    return new Response(JSON.stringify({ error: 'Not the host' }), {
      status: 403,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const playersData = await env.DB.prepare('SELECT * FROM players WHERE room_code = ? AND (is_spectator = 0 OR is_spectator IS NULL) ORDER BY COALESCE(seat_number, 999), is_host DESC, name ASC')
    .bind(roomCode.toUpperCase())
    .all<{
      id: string;
      is_spectator?: number;
      seat_number?: number | null;
    }>();

  const activePlayers = playersData.results.filter(p => !p.is_spectator || p.is_spectator === 0);

  if (activePlayers.length < 2) {
    return new Response(JSON.stringify({ error: 'Need at least 2 players' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const deck = shuffleDeck(createStandardDeck());
  const hands = dealCards(deck, activePlayers.length);

  for (let i = 0; i < activePlayers.length; i++) {
    const player = activePlayers[i];
    await env.DB.prepare('UPDATE players SET hand_json = ?, card_count = ? WHERE id = ?')
      .bind(
        JSON.stringify(hands[i]),
        hands[i].length,
        player.id,
      )
      .run();
  }

  const hostPlayer = activePlayers[0];
  const hostHand = hands[0];

  if (hostHand.length === 0) {
    return new Response(JSON.stringify({ error: 'Host has no cards' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const firstCard = hostHand[0];
  hostHand.shift();

  await env.DB.prepare('UPDATE players SET hand_json = ?, card_count = ? WHERE id = ?')
    .bind(
      JSON.stringify(hostHand),
      hostHand.length,
      hostPlayer.id,
    )
    .run();

  const playerIds = activePlayers.map(p => p.id);
  const initialGameState: GameState = {
    drawPile: deck,
    discardPile: [],
    activeColor: CardColor.red,
    currentTurnPlayerId: hostPlayer.id,
    direction: 1,
    pendingDrawCount: 0,
    lastPlayedCardJson: null,
    pendingWildColorChoice: null,
    unoCalled: {},
    stateVersion: roomData.state_version,
    lastActivity: new Date().toISOString(),
    winnerPlayerId: null,
    winnerTimestamp: null,
    lastPlayedCardAnimationId: null,
  };

  const playerIdsOrdered = await getPlayerIds(roomCode.toUpperCase(), env);

  const chosenColor = firstCard.isWild ? CardColor.red : undefined;
  const gameState = processCardPlay(
    initialGameState,
    firstCard,
    chosenColor,
    hostPlayer.id,
    playerIdsOrdered,
  );

  await env.DB.prepare(
    `UPDATE rooms SET status = ?, game_state_json = ?, current_turn_player_id = ?, direction = ?, active_color = ?, pending_draw_count = ?, state_version = ?, last_activity = ?
     WHERE code = ?`
  )
    .bind(
      RoomStatus.playing,
      JSON.stringify(gameState),
      gameState.currentTurnPlayerId,
      gameState.direction,
      gameState.activeColor,
      gameState.pendingDrawCount,
      gameState.stateVersion,
      gameState.lastActivity,
      roomCode.toUpperCase(),
    )
    .run();

  const room = await getRoomWithPlayers(roomCode.toUpperCase(), env);
  if (!room) {
    return new Response(JSON.stringify({
      type: 'ROOM_DELETED',
      reason: 'NOT_FOUND',
      events: [createEvent(GameEventType.ROOM_DELETED, playerId, { reason: 'NOT_FOUND' })],
    }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify(room), {
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handlePlayCard(request: Request, env: Env): Promise<Response> {
  const body = await request.json() as {
    roomCode: string;
    playerId: string;
    card: any;
    chosenColor?: string;
  };
  const { roomCode, playerId, card, chosenColor } = body;

  const roomData = await env.DB.prepare('SELECT * FROM rooms WHERE code = ?')
    .bind(roomCode.toUpperCase())
    .first<{
      game_state_json: string;
      current_turn_player_id: string;
      state_version: number;
    }>();

  if (!roomData) {
    return new Response(JSON.stringify({ error: 'Room not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  if (roomData.current_turn_player_id !== playerId) {
    return new Response(JSON.stringify({ error: 'Not your turn' }), {
      status: 403,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const gameState = JSON.parse(roomData.game_state_json) as GameState;
  const player = await env.DB.prepare('SELECT * FROM players WHERE id = ? AND room_code = ?')
    .bind(playerId, roomCode.toUpperCase())
    .first<{ hand_json: string }>();

  if (!player) {
    return new Response(JSON.stringify({ error: 'Player not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const hand = JSON.parse(player.hand_json) as any[];
  const cardIndex = hand.findIndex(
    (c) => c.color === card.color && c.type === card.type && c.number === card.number
  );

  if (cardIndex === -1) {
    return new Response(JSON.stringify({ error: 'Card not in hand' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const playerData = await env.DB.prepare('SELECT * FROM players WHERE id = ? AND room_code = ?')
    .bind(playerId, roomCode.toUpperCase())
    .first<{ is_spectator?: boolean }>();

  if (playerData && playerData.is_spectator) {
    return new Response(JSON.stringify({ error: 'Spectators cannot play cards' }), {
      status: 403,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const topCard = gameState.discardPile[gameState.discardPile.length - 1];

  if (!canPlayCard(card, topCard, gameState.activeColor, gameState.pendingDrawCount, hand)) {
    return new Response(JSON.stringify({ error: 'Invalid card' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  if (card.isWild && !chosenColor) {
    return new Response(JSON.stringify({ error: 'Wild card requires color choice' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  hand.splice(cardIndex, 1);

  const updatedGameState = processCardPlay(
    gameState,
    card,
    chosenColor as CardColor | undefined,
    playerId,
    await getPlayerIds(roomCode.toUpperCase(), env),
  );

  let winnerDetected = false;
  let winnerPlayerId: string | null = null;

  if (hand.length === 0) {
    winnerDetected = true;
    winnerPlayerId = playerId;
    updatedGameState.winnerPlayerId = playerId;
    updatedGameState.winnerTimestamp = new Date().toISOString();
    updatedGameState.currentTurnPlayerId = null;
  }

  await env.DB.prepare('UPDATE players SET hand_json = ?, card_count = ? WHERE id = ?')
    .bind(JSON.stringify(hand), hand.length, playerId)
    .run();

  await env.DB.prepare(
    `UPDATE rooms SET status = ?, game_state_json = ?, current_turn_player_id = ?, direction = ?, active_color = ?, pending_draw_count = ?, state_version = ?, last_activity = ?
     WHERE code = ?`
  )
    .bind(
      winnerDetected ? RoomStatus.finished : RoomStatus.playing,
      JSON.stringify(updatedGameState),
      updatedGameState.currentTurnPlayerId,
      updatedGameState.direction,
      updatedGameState.activeColor,
      updatedGameState.pendingDrawCount,
      roomData.state_version + 1,
      updatedGameState.lastActivity,
      roomCode.toUpperCase(),
    )
    .run();

  if (!winnerDetected) {
    await checkUnoCall(updatedGameState, playerId, hand.length, env, roomCode.toUpperCase());
  } else {
    setTimeout(async () => {
      await env.DB.prepare('DELETE FROM players WHERE room_code = ?')
        .bind(roomCode.toUpperCase())
        .run();
      await env.DB.prepare('DELETE FROM rooms WHERE code = ?')
        .bind(roomCode.toUpperCase())
        .run();
    }, 10000);
  }

  const room = await getRoomWithPlayers(roomCode.toUpperCase(), env);
  if (!room) {
    return new Response(JSON.stringify({
      type: 'ROOM_DELETED',
      reason: 'NOT_FOUND',
      events: [createEvent(GameEventType.ROOM_DELETED, playerId, { reason: 'NOT_FOUND' })],
    }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify(room), {
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handleDrawCard(request: Request, env: Env): Promise<Response> {
  const body = await request.json() as { roomCode: string; playerId: string };
  const { roomCode, playerId } = body;

  const roomData = await env.DB.prepare('SELECT * FROM rooms WHERE code = ?')
    .bind(roomCode.toUpperCase())
    .first<{
      game_state_json: string;
      current_turn_player_id: string;
      state_version: number;
    }>();

  if (!roomData || roomData.current_turn_player_id !== playerId) {
    return new Response(JSON.stringify({ error: 'Not your turn' }), {
      status: 403,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const gameState = JSON.parse(roomData.game_state_json) as GameState;
  const player = await env.DB.prepare('SELECT * FROM players WHERE id = ? AND room_code = ?')
    .bind(playerId, roomCode.toUpperCase())
    .first<{ hand_json: string }>();

  if (!player) {
    return new Response(JSON.stringify({ error: 'Player not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  let drawCount = 1;
  if (gameState.pendingDrawCount > 0) {
    drawCount = gameState.pendingDrawCount;
  }

  const hand = JSON.parse(player.hand_json) as any[];
  let drawPile = gameState.drawPile;

  if (drawPile.length < drawCount) {
    const discardPile = gameState.discardPile.slice(0, -1);
    drawPile = shuffleDeck(discardPile);
    gameState.discardPile = [gameState.discardPile[gameState.discardPile.length - 1]];
  }

  const drawnCards = drawPile.splice(0, drawCount);
  hand.push(...drawnCards);

  const updatedGameState: GameState = {
    ...gameState,
    drawPile,
    pendingDrawCount: 0,
    currentTurnPlayerId: getNextPlayer(
      playerId,
      await getPlayerIds(roomCode.toUpperCase(), env),
      gameState.direction,
    ),
    stateVersion: roomData.state_version + 1,
    lastActivity: new Date().toISOString(),
  };

  await env.DB.prepare('UPDATE players SET hand_json = ?, card_count = ? WHERE id = ?')
    .bind(JSON.stringify(hand), hand.length, playerId)
    .run();

  await env.DB.prepare(
    `UPDATE rooms SET game_state_json = ?, current_turn_player_id = ?, pending_draw_count = ?, state_version = ?, last_activity = ?
     WHERE code = ?`
  )
    .bind(
      JSON.stringify(updatedGameState),
      updatedGameState.currentTurnPlayerId,
      0,
      updatedGameState.stateVersion,
      updatedGameState.lastActivity,
      roomCode.toUpperCase(),
    )
    .run();

  const room = await getRoomWithPlayers(roomCode.toUpperCase(), env);
  if (!room) {
    return new Response(JSON.stringify({
      type: 'ROOM_DELETED',
      reason: 'NOT_FOUND',
      events: [createEvent(GameEventType.ROOM_DELETED, playerId, { reason: 'NOT_FOUND' })],
    }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify(room), {
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handleCallUno(request: Request, env: Env): Promise<Response> {
  const body = await request.json() as { roomCode: string; playerId: string };
  const { roomCode, playerId } = body;

  const roomData = await env.DB.prepare('SELECT * FROM rooms WHERE code = ?')
    .bind(roomCode.toUpperCase())
    .first<{ game_state_json: string; state_version: number }>();

  if (!roomData) {
    return new Response(JSON.stringify({ error: 'Room not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const gameState = JSON.parse(roomData.game_state_json) as GameState;
  const player = await env.DB.prepare('SELECT * FROM players WHERE id = ? AND room_code = ?')
    .bind(playerId, roomCode.toUpperCase())
    .first<{ hand_json: string }>();

  if (!player) {
    return new Response(JSON.stringify({ error: 'Player not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const hand = JSON.parse(player.hand_json) as any[];

  if (hand.length !== 1) {
    return new Response(JSON.stringify({ error: 'Must have exactly 1 card' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  if (gameState.unoCalled[playerId]) {
    return new Response(JSON.stringify({ error: 'UNO already called' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  gameState.unoCalled[playerId] = true;
  gameState.stateVersion = roomData.state_version + 1;
  gameState.lastActivity = new Date().toISOString();

  await env.DB.prepare('UPDATE rooms SET game_state_json = ?, state_version = ?, last_activity = ? WHERE code = ?')
    .bind(JSON.stringify(gameState), gameState.stateVersion, gameState.lastActivity, roomCode.toUpperCase())
    .run();

  const room = await getRoomWithPlayers(roomCode.toUpperCase(), env);
  if (!room) {
    return new Response(JSON.stringify({
      type: 'ROOM_DELETED',
      reason: 'NOT_FOUND',
      events: [createEvent(GameEventType.ROOM_DELETED, playerId, { reason: 'NOT_FOUND' })],
    }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify(room), {
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handlePassTurn(request: Request, env: Env): Promise<Response> {
  const body = await request.json() as { roomCode: string; playerId: string };
  const { roomCode, playerId } = body;

  const roomData = await env.DB.prepare('SELECT * FROM rooms WHERE code = ?')
    .bind(roomCode.toUpperCase())
    .first<{
      game_state_json: string;
      current_turn_player_id: string;
      state_version: number;
    }>();

  if (!roomData || roomData.current_turn_player_id !== playerId) {
    return new Response(JSON.stringify({ error: 'Not your turn' }), {
      status: 403,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const gameState = JSON.parse(roomData.game_state_json) as GameState;

  const updatedGameState: GameState = {
    ...gameState,
    currentTurnPlayerId: getNextPlayer(
      playerId,
      await getPlayerIds(roomCode.toUpperCase(), env),
      gameState.direction,
    ),
    stateVersion: roomData.state_version + 1,
    lastActivity: new Date().toISOString(),
  };

  await env.DB.prepare(
    `UPDATE rooms SET game_state_json = ?, current_turn_player_id = ?, state_version = ?, last_activity = ?
     WHERE code = ?`
  )
    .bind(
      JSON.stringify(updatedGameState),
      updatedGameState.currentTurnPlayerId,
      updatedGameState.stateVersion,
      updatedGameState.lastActivity,
      roomCode.toUpperCase(),
    )
    .run();

  const room = await getRoomWithPlayers(roomCode.toUpperCase(), env);
  if (!room) {
    return new Response(JSON.stringify({
      type: 'ROOM_DELETED',
      reason: 'NOT_FOUND',
      events: [createEvent(GameEventType.ROOM_DELETED, playerId, { reason: 'NOT_FOUND' })],
    }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify(room), {
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handleSync(request: Request, env: Env): Promise<Response> {
  const body = await request.json() as { roomCode: string; playerId: string; stateVersion: number };
  const { roomCode, playerId, stateVersion } = body;

  const room = await getRoomWithPlayers(roomCode.toUpperCase(), env);

  if (!room) {
    return new Response(JSON.stringify({
      type: 'ROOM_DELETED',
      reason: 'NOT_FOUND',
      events: [createEvent(GameEventType.ROOM_DELETED, playerId, { reason: 'NOT_FOUND' })],
    }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  if (room.gameState && room.gameState.stateVersion <= stateVersion) {
    return new Response(null, { status: 204 });
  }

  return new Response(JSON.stringify(room), {
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handlePoll(code: string, searchParams: URLSearchParams, env: Env): Promise<Response> {
  const playerId = searchParams.get('playerId');
  const lastKnownVersion = parseInt(searchParams.get('lastKnownVersion') || '0', 10);
  const isSpectator = searchParams.get('isSpectator') === 'true';

  try {
    // First check if room exists and get its state_version
    const roomStateVersion = await env.DB.prepare('SELECT state_version FROM rooms WHERE code = ?')
      .bind(code.toUpperCase())
      .first<{ state_version: number }>();

    if (!roomStateVersion) {
      return new Response(JSON.stringify({
        type: 'ROOM_DELETED',
        reason: 'NOT_FOUND',
        events: [createEvent(GameEventType.ROOM_DELETED, playerId || undefined, { reason: 'NOT_FOUND' })],
      }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // If room has changed, return immediately
    if (roomStateVersion.state_version > lastKnownVersion) {
      const room = await getRoomWithPlayers(code.toUpperCase(), env);
      if (room) {
        return new Response(JSON.stringify(room), {
          headers: { 'Content-Type': 'application/json' },
        });
      }
    }

    // Long poll: wait for changes
    const maxWait = isSpectator ? 5 : 15;
    const checkInterval = isSpectator ? 2000 : 1000;

    for (let i = 0; i < maxWait; i++) {
      await new Promise(resolve => setTimeout(resolve, checkInterval));
      try {
        const roomData = await env.DB.prepare('SELECT state_version FROM rooms WHERE code = ?')
          .bind(code.toUpperCase())
          .first<{ state_version: number }>();

        if (!roomData) {
          return new Response(JSON.stringify({
            type: 'ROOM_DELETED',
            reason: 'NOT_FOUND',
            events: [createEvent(GameEventType.ROOM_DELETED, playerId || undefined, { reason: 'NOT_FOUND' })],
          }), {
            headers: { 'Content-Type': 'application/json' },
          });
        }

        if (roomData.state_version > lastKnownVersion) {
          const updatedRoom = await getRoomWithPlayers(code.toUpperCase(), env);
          if (updatedRoom) {
            return new Response(JSON.stringify(updatedRoom), {
              headers: { 'Content-Type': 'application/json' },
            });
          }
        }
      } catch (e) {
        return new Response(JSON.stringify({
          type: 'ROOM_DELETED',
          reason: 'NOT_FOUND',
          events: [createEvent(GameEventType.ROOM_DELETED, playerId || undefined, { reason: 'NOT_FOUND' })],
        }), {
          headers: { 'Content-Type': 'application/json' },
        });
      }
    }

    return new Response(JSON.stringify({ changed: false }), {
      status: 304,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({
      type: 'ROOM_DELETED',
      reason: 'NOT_FOUND',
      events: [createEvent(GameEventType.ROOM_DELETED, playerId || undefined, { reason: 'NOT_FOUND' })],
    }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

async function handleHeartbeat(request: Request, env: Env): Promise<Response> {

  const body = await request.json() as { roomCode: string; playerId: string };
  const { roomCode, playerId } = body;

  await env.DB.prepare('UPDATE players SET last_seen = ? WHERE id = ? AND room_code = ?')
    .bind(new Date().toISOString(), playerId, roomCode.toUpperCase())
    .run();

  return new Response(JSON.stringify({ success: true }), {
    headers: { 'Content-Type': 'application/json' },
  });
}

async function cleanupInactiveRooms(env: Env): Promise<void> {
  const cutoff = new Date(Date.now() - 5 * 60 * 1000).toISOString();
  const staleRooms = await env.DB.prepare('SELECT code FROM rooms WHERE last_activity < ?')
    .bind(cutoff)
    .all<{ code: string }>();

  if (!staleRooms.results.length) return;

  const codes = staleRooms.results.map((r) => r.code);
  const placeholders = codes.map(() => '?').join(', ');

  await env.DB.prepare(
    `DELETE FROM players WHERE room_code IN (${placeholders})`
  )
    .bind(...codes)
    .run();

  await env.DB.prepare(
    `DELETE FROM rooms WHERE code IN (${placeholders})`
  )
    .bind(...codes)
    .run();
}

function generateRoomCode(): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let result = '';
  for (let i = 0; i < 6; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

interface PlayerRow {
  id: string;
  name: string;
  room_code: string;
  is_host: number;
  is_spectator?: number;
  seat_number?: number | null;
  hand_json?: string | null;
  last_seen: string;
}

async function getRoomWithPlayers(roomCode: string, env: Env): Promise<Room | null> {
  const roomData = await env.DB.prepare('SELECT * FROM rooms WHERE code = ?')
    .bind(roomCode)
    .first<{
      code: string;
      host_id: string;
      status: string;
      game_state_json: string;
      current_turn_player_id: string | null;
      direction: number;
      active_color: string;
      pending_draw_count: number;
      state_version: number;
      last_activity: string;
    }>();

  if (!roomData) {
    return null;
  }

  const playerRows = await env.DB.prepare('SELECT * FROM players WHERE room_code = ? ORDER BY COALESCE(seat_number, 999), is_host DESC, name ASC')
    .bind(roomCode)
    .all<PlayerRow>();

  const players: Player[] = playerRows.results.map((raw) => ({
    id: raw.id,
    name: raw.name,
    roomCode: raw.room_code,
    isHost: raw.is_host === 1,
    isSpectator: (raw.is_spectator ?? 0) === 1,
    seatNumber: raw.seat_number ?? undefined,
    hand: raw.hand_json ? JSON.parse(raw.hand_json) : [],
    lastSeen: raw.last_seen,
  }));

  let gameState: GameState | null = null;
  if ((roomData.status === RoomStatus.playing || roomData.status === RoomStatus.finished) && roomData.game_state_json) {
    try {
      gameState = JSON.parse(roomData.game_state_json);
    } catch {
      gameState = null;
    }
  }

  return {
    code: roomData.code,
    hostId: roomData.host_id,
    status: roomData.status as RoomStatus,
    gameState,
    players,
    lastActivity: roomData.last_activity,
    stateVersion: roomData.state_version,
  };
}

async function getPlayerIds(roomCode: string, env: Env): Promise<string[]> {
  const players = await env.DB.prepare('SELECT id, seat_number FROM players WHERE room_code = ? AND (is_spectator = 0 OR is_spectator IS NULL) ORDER BY COALESCE(seat_number, 999), is_host DESC, name ASC')
    .bind(roomCode)
    .all<{ id: string; seat_number?: number | null }>();

  return players.results.map(p => p.id);
}

async function incrementRoomStateVersion(roomCode: string, env: Env): Promise<void> {
  const now = new Date().toISOString();
  await env.DB.prepare('UPDATE rooms SET state_version = state_version + 1, last_activity = ? WHERE code = ?')
    .bind(now, roomCode.toUpperCase())
    .run();
}

function createEvent(type: GameEventType, playerId?: string, data?: any): GameEvent {
  return {
    type,
    playerId,
    data,
    timestamp: new Date().toISOString(),
    eventId: `${type}_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
  };
}
async function handleGetRTCSignals(playerId: string, env: Env): Promise<Response> {
  if (!playerId) {
    return new Response(JSON.stringify({ error: 'Missing playerId' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const signals = await env.DB.prepare(
    'SELECT * FROM rtc_signals WHERE to_player_id = ? ORDER BY created_at ASC'
  )
    .bind(playerId)
    .all<{
      id: number;
      room_code: string;
      from_player_id: string;
      to_player_id: string;
      signal_type: string;
      signal_data: string;
      created_at: string;
    }>();

  if (signals.results.length > 0) {
    const ids = signals.results.map(s => s.id);
    const placeholders = ids.map(() => '?').join(',');
    await env.DB.prepare(`DELETE FROM rtc_signals WHERE id IN (${placeholders})`)
      .bind(...ids)
      .run();
  }

  return new Response(JSON.stringify({ signals: signals.results }), {
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handleSendRTCSignal(request: Request, env: Env): Promise<Response> {
  try {
    const body = await request.json() as {
      roomCode: string;
      fromPlayerId: string;
      toPlayerId: string;
      signalType: string;
      signalData: string;
    };

    const { roomCode, fromPlayerId, toPlayerId, signalType, signalData } = body;

    if (!roomCode || !fromPlayerId || !toPlayerId || !signalType || !signalData) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    await env.DB.prepare(
      `INSERT INTO rtc_signals (room_code, from_player_id, to_player_id, signal_type, signal_data)
       VALUES (?, ?, ?, ?, ?)`
    )
      .bind(roomCode.toUpperCase(), fromPlayerId, toPlayerId, signalType, signalData)
      .run();

    return new Response(JSON.stringify({ success: true }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: 'INTERNAL_ERROR' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}
