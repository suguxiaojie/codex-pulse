#!/usr/bin/python3
"""Isolated WebSocket peer for the shared-daemon transport tests. No model calls."""
import base64
import hashlib
import json
import os
import socket
import struct

peer = socket.socket(fileno=0)
mode = os.environ.get('PULSE_PROXY_FIXTURE', 'normal')
header = b''
while b'\r\n\r\n' not in header:
    header += peer.recv(4096)
key = next(x.split(b':', 1)[1].strip() for x in header.split(b'\r\n') if x.lower().startswith(b'sec-websocket-key:'))
accept = base64.b64encode(hashlib.sha1(key + b'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest())
if mode == 'bad-upgrade':
    accept = b'invalid'
peer.sendall(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + b'\r\n\r\n')

def read(n):
    result = b''
    while len(result) < n:
        data = peer.recv(n - len(result))
        if not data:
            raise EOFError()
        result += data
    return result

def frame(op, data, final=True):
    n = len(data)
    h = bytes([(128 if final else 0) | op])
    h += bytes([n]) if n < 126 else b'\x7e' + struct.pack('>H', n)
    peer.sendall(h + data)

try:
    while True:
        a, b = read(2)
        n = b & 127
        if n == 126:
            n = struct.unpack('>H', read(2))[0]
        elif n == 127:
            n = struct.unpack('>Q', read(8))[0]
        assert b & 128
        mask = read(4)
        raw = bytes(v ^ mask[i % 4] for i, v in enumerate(read(n)))
        if a & 15 == 10:
            continue
        message = json.loads(raw)
        if 'id' not in message:
            continue
        if message['method'] != 'initialize':
            if mode == 'oversized':
                peer.sendall(b'\x81\x7f' + struct.pack('>Q', 10 * 1024 * 1024))
                break
            if mode == 'closed':
                frame(8, b'')
                break
            if mode == 'wrong-id':
                frame(1, json.dumps({'id': -1, 'result': {}}).encode())
            if mode == 'rpc-error':
                frame(1, json.dumps({'id': message['id'], 'error': {'code': -1}}).encode())
                continue
        result = {} if message['method'] == 'initialize' else {'data': ['fixture-thread']}
        response = json.dumps({'id': message['id'], 'result': result}).encode()
        frame(9, b'ping')
        frame(1, response[:8], final=False)
        frame(0, response[8:])
except (EOFError, BrokenPipeError, ConnectionResetError):
    pass
