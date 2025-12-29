import zmq
import time
import random
import json

# --- ZMQ SETUP (The E2 Interface) ---
context = zmq.Context()
socket = context.socket(zmq.PUB)  # Publisher Mode
socket.bind("tcp://*:5555")       # Broadcast on Port 5555

print("--- E2 TRAFFIC SIMULATOR STARTED ---")
print("Simulating 5G Network Load over ZMQ...")

# Start with a baseline load
network_load = 30

while True:
    # 1. Simulate "Walking" Traffic (Realistic Patterns)
    # Instead of random jumps, it creeps up or down (Trend)
    change = random.randint(-10, 15) # Tendency to go up slightly
    network_load += change
    
    # Keep it between 0 and 100
    network_load = max(0, min(100, network_load))
    
    # 2. Package the message (JSON format)
    message = {"load": network_load, "type": "REPORT"}
    
    # 3. Send it over the "E2 Interface"
    print(f"Sending Load Report: {network_load}%")
    socket.send_json(message)
    
    # Send every 1 second
    time.sleep(1)