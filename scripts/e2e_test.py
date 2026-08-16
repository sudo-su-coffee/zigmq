import socket

HOST = "127.0.0.1"
PORT = 4422


def read_until(sock: socket.socket, marker: bytes) -> bytes:
    data = b""
    while marker not in data:
        chunk = sock.recv(4096)
        if not chunk:
            raise RuntimeError(f"connection closed before {marker!r}: {data!r}")
        data += chunk
    return data


subscriber = socket.create_connection((HOST, PORT), timeout=3)
publisher = socket.create_connection((HOST, PORT), timeout=3)
try:
    assert b"+OK zigmq ready\r\n" in read_until(subscriber, b"\r\n")
    assert b"+OK zigmq ready\r\n" in read_until(publisher, b"\r\n")

    subscriber.sendall(b"SUB demo\r\n")
    assert b"+OK SUB\r\n" in read_until(subscriber, b"\r\n")

    publisher.sendall(b"PUB demo hello edge\r\n")
    publisher_reply = read_until(publisher, b"\r\n")
    assert b"+OK PUB\r\n" in publisher_reply

    delivered = read_until(subscriber, b"\r\nhello edge\r\n")
    assert b"MSG demo 10\r\nhello edge\r\n" in delivered

    publisher.sendall(b"PING\r\n")
    assert b"PONG\r\n" in read_until(publisher, b"\r\n")

    subscriber.sendall(b"UNSUB demo\r\n")
    assert b"+OK UNSUB\r\n" in read_until(subscriber, b"\r\n")

    subscriber.sendall(b"QUIT\r\n")
    assert b"+OK BYE\r\n" in read_until(subscriber, b"\r\n")
finally:
    subscriber.close()
    publisher.sendall(b"QUIT\r\n")
    publisher.close()

print("E2E_OK")
