#!/usr/bin/env python3
"""
Minimal WebSocket signaling server for MathsChat P2P connections.
Relays SDP offers/answers and ICE candidates between two peers in a room.
"""

import asyncio
import json
import argparse
from typing import Dict, Set
from websockets.server import serve
from websockets.exceptions import ConnectionClosed


class SignalingServer:
    def __init__(self):
        # room -> set of websocket connections
        self.rooms: Dict[str, Set] = {}

    async def handle_client(self, websocket, path):
        """Handle a WebSocket client connection."""
        room = None
        try:
            async for message in websocket:
                data = json.loads(message)
                action = data.get("action")

                if action == "join":
                    room = data.get("room")
                    if not room:
                        await websocket.send(json.dumps({
                            "action": "error",
                            "error": "Missing room"
                        }))
                        continue

                    # Initialize room if needed
                    if room not in self.rooms:
                        self.rooms[room] = set()

                    # Check room capacity (max 2 peers)
                    if len(self.rooms[room]) >= 2:
                        await websocket.send(json.dumps({
                            "action": "error",
                            "error": "Room is full (max 2 peers)"
                        }))
                        continue

                    # Add client to room
                    self.rooms[room].add(websocket)
                    peer_count = len(self.rooms[room])

                    # Notify client
                    await websocket.send(json.dumps({
                        "action": "joined",
                        "room": room,
                        "peers": peer_count
                    }))

                    # Notify other peer if present
                    for peer in list(self.rooms[room]):
                        if peer != websocket:
                            await peer.send(json.dumps({
                                "action": "peer_joined",
                                "room": room
                            }))

                elif action == "relay":
                    if not room or room not in self.rooms:
                        await websocket.send(json.dumps({
                            "action": "error",
                            "error": "Not in a room"
                        }))
                        continue

                    payload = data.get("payload")
                    if not payload:
                        await websocket.send(json.dumps({
                            "action": "error",
                            "error": "Missing payload"
                        }))
                        continue

                    # Relay to the other peer in the room
                    for peer in list(self.rooms[room]):
                        if peer != websocket:
                            await peer.send(json.dumps({
                                "action": "relayed",
                                "room": room,
                                "payload": payload
                            }))

                elif action == "leave":
                    if room and room in self.rooms:
                        self.rooms[room].discard(websocket)
                        if len(self.rooms[room]) == 0:
                            del self.rooms[room]
                        else:
                            # Notify remaining peer
                            for peer in list(self.rooms[room]):
                                await peer.send(json.dumps({
                                    "action": "peer_left",
                                    "room": room
                                }))
                    break

        except ConnectionClosed:
            pass
        finally:
            # Clean up on disconnect
            if room and room in self.rooms:
                self.rooms[room].discard(websocket)
                if len(self.rooms[room]) == 0:
                    del self.rooms[room]
                else:
                    # Notify remaining peer
                    for peer in list(self.rooms[room]):
                        try:
                            await peer.send(json.dumps({
                                "action": "peer_left",
                                "room": room
                            }))
                        except:
                            pass


async def main():
    parser = argparse.ArgumentParser(description="MathsChat signaling server")
    parser.add_argument("--port", type=int, default=8080, help="WebSocket port")
    parser.add_argument("--host", type=str, default="localhost", help="Bind host")
    args = parser.parse_args()

    server = SignalingServer()
    print(f"Signaling server listening on ws://{args.host}:{args.port}")

    async with serve(server.handle_client, args.host, args.port):
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    asyncio.run(main())
