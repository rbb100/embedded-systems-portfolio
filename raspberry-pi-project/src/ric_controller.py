from flask import Flask, redirect, url_for
import RPi.GPIO as GPIO
import board
import adafruit_dht
import os
import time
import threading
import zmq 

app = Flask(__name__)

# --- GLOBAL VARIABLES ---
current_network_load = 0 
control_mode = "AUTO" 
last_zmq_time = 0 

# SIMULATION FLAGS
force_override = False    
override_end_time = 0
light_threshold = 70      

# --- 1. HARDWARE SETUP ---
ADC_CS  = 5; ADC_CLK = 6; ADC_DI  = 13; ADC_DO  = 19
RED_PIN = 17; GREEN_PIN = 27; DHT_PIN = board.D4 

GPIO.setmode(GPIO.BCM); GPIO.setwarnings(False)
GPIO.setup(RED_PIN, GPIO.OUT); GPIO.setup(GREEN_PIN, GPIO.OUT)
GPIO.setup(ADC_CS, GPIO.OUT); GPIO.setup(ADC_CLK, GPIO.OUT)
GPIO.setup(ADC_DI, GPIO.OUT); GPIO.setup(ADC_DO, GPIO.IN)

green_pwm = GPIO.PWM(GREEN_PIN, 100)
green_pwm.start(0)

try:
    dht_device = adafruit_dht.DHT11(DHT_PIN)
except:
    pass

# --- 2. ZMQ LISTENER ---
def e2_listener():
    global current_network_load, last_zmq_time
    context = zmq.Context()
    socket = context.socket(zmq.SUB)
    socket.connect("tcp://localhost:5555") 
    socket.subscribe("")
    
    while True:
        try:
            if socket.poll(100): 
                data = socket.recv_json()
                if not force_override:
                    current_network_load = data['load']
                last_zmq_time = time.time()
        except:
            pass

t = threading.Thread(target=e2_listener)
t.daemon = True
t.start()

# --- 3. SENSOR FUNCTIONS ---
def _send_bit(bit):
    GPIO.output(ADC_DI, bit); GPIO.output(ADC_CLK, GPIO.HIGH); GPIO.output(ADC_CLK, GPIO.LOW)

def get_light_level():
    GPIO.output(ADC_CS, GPIO.HIGH); GPIO.output(ADC_CLK, GPIO.LOW); GPIO.output(ADC_CS, GPIO.LOW)
    _send_bit(1); _send_bit(1); _send_bit(0)
    value = 0
    for i in range(8):
        GPIO.output(ADC_CLK, GPIO.HIGH); GPIO.output(ADC_CLK, GPIO.LOW)
        if GPIO.input(ADC_DO): value |= (1 << (7 - i))
    GPIO.output(ADC_CS, GPIO.HIGH)
    return value

def read_dht_safe():
    try:
        h = dht_device.humidity; t = dht_device.temperature
        return (h, t) if h is not None and t is not None else (None, None)
    except:
        return None, None

def get_cpu_temp():
    try:
        return os.popen('vcgencmd measure_temp').readline().replace("temp=","").replace("'C\n","")
    except:
        return "0.0"

# --- 4. AI ENGINE ---
class TrafficPredictorAI:
    def __init__(self):
        self.history = []; self.max_memory = 10
    def add_data(self, load):
        self.history.append(load)
        if len(self.history) > self.max_memory: self.history.pop(0)
    def predict_next(self):
        if len(self.history) < 2: return 0
        n = len(self.history)
        slope = (self.history[-1] - self.history[0]) / n
        return max(0, min(100, self.history[-1] + slope))

ai_agent = TrafficPredictorAI()

# --- 5. ROUTES & TOOLS ---
@app.route('/set_mode/<mode>')
def set_mode(mode):
    global control_mode
    control_mode = mode.upper()
    return redirect(url_for('dashboard'))

@app.route('/trigger_spike')
def trigger_spike():
    global force_override, override_end_time, current_network_load
    force_override = True
    current_network_load = 99  
    override_end_time = time.time() + 5 
    return redirect(url_for('dashboard'))

@app.route('/trigger_drop')
def trigger_drop():
    global force_override, override_end_time, current_network_load
    force_override = True
    current_network_load = 5   
    override_end_time = time.time() + 5 
    return redirect(url_for('dashboard'))

@app.route('/')
def dashboard():
    global current_network_load, control_mode, force_override, light_threshold, last_zmq_time
    
    # ZMQ Status
    time_since_data = time.time() - last_zmq_time
    if time_since_data < 3:
        zmq_badge = '<span class="badge badge-ok">⚡ ZMQ: CONNECTED</span>'
    else:
        zmq_badge = '<span class="badge badge-err">⚠️ ZMQ: DISCONNECTED</span>'
        if not force_override: current_network_load = 0 

    # Check Simulation Timer
    if force_override and (time.time() > override_end_time):
        force_override = False 
    
    # AI & Sensors
    ai_agent.add_data(current_network_load)
    predicted_load = ai_agent.predict_next()
    
    light_level = get_light_level()
    humidity, room_temp = read_dht_safe()
    cpu_temp = get_cpu_temp()
    
    hum_str = f"{humidity}%" if humidity else "--"
    room_temp_str = f"{room_temp}°C" if room_temp else "--"

    # Day/Night Status (Visual Only now)
    if light_level < light_threshold:
        day_night_status = "🌙 NIGHT TIME"
        env_style = "background-color: #2c3e50; color: white;" 
    else:
        day_night_status = "☀️ DAY TIME"
        env_style = "background-color: #fff9c4; color: #333;" 

    # --- UPDATED CONTROL LOGIC (Aggressive Power Save) ---
    if control_mode == "AUTO":
        
        # CHANGED: Removed "and is_night". Now it sleeps anytime load < 30.
        if current_network_load < 30:
            state_text = "SLEEP MODE ACTIVATED (Low Load Saving)"
            state_color = "#ff4d4d" # Red
            green_pwm.ChangeDutyCycle(0)
            GPIO.output(RED_PIN, GPIO.HIGH)
            
        elif predicted_load > 85:
            state_text = "PREDICTIVE BOOST (AI Detected Spike)"
            state_color = "#9C27B0" # Purple
            GPIO.output(RED_PIN, GPIO.LOW)
            green_pwm.ChangeDutyCycle(100)
            
        else:
            state_text = f"ACTIVE MODE (Dynamic Load: {current_network_load}%)"
            state_color = "#4CAF50" # Green
            GPIO.output(RED_PIN, GPIO.LOW)
            green_pwm.ChangeDutyCycle(current_network_load)
            
    elif control_mode == "SLEEP":
        state_text = "⛔ ADMIN OVERRIDE: FORCED SLEEP"
        state_color = "#D32F2F"; green_pwm.ChangeDutyCycle(0); GPIO.output(RED_PIN, GPIO.HIGH)
    elif control_mode == "ACTIVE":
        state_text = "⚡ ADMIN OVERRIDE: FORCED ACTIVE"
        state_color = "#388E3C"; GPIO.output(RED_PIN, GPIO.LOW); green_pwm.ChangeDutyCycle(100)

    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Eco-RIC</title>
        <meta http-equiv="refresh" content="2">
        <style>
            body {{ font-family: 'Segoe UI', sans-serif; text-align: center; background: #eaeff2; margin-top: 20px; }}
            .card {{ background: white; width: 650px; margin: 0 auto; padding: 25px; border-radius: 15px; box-shadow: 0 10px 25px rgba(0,0,0,0.1); }}
            h1 {{ margin-top: 0; color: #2E7D32; }}
            .big {{ font-size: 36px; font-weight: bold; }}
            .status-box {{ padding: 15px; margin-top: 20px; border-radius: 8px; color: {state_color}; border: 3px solid {state_color}; background: {state_color}10; font-weight: bold; font-size: 18px; }}
            .env-box {{ padding: 15px; border-radius: 10px; margin: 15px 0; {env_style} display: flex; justify-content: space-around; align-items: center; }}
            
            /* BUTTONS */
            .btn {{ padding: 10px 15px; margin: 0 5px; text-decoration: none; border-radius: 5px; color: white; font-weight: bold; font-size: 13px; display:inline-block; transition: 0.2s; }}
            .btn:hover {{ opacity: 0.8; transform: scale(1.05); }}
            .btn-a {{ background: #607D8B; }} .btn-s {{ background: #ef5350; }} .btn-ac {{ background: #66BB6A; }}
            .btn-spike {{ background: #9C27B0; border-bottom: 3px solid #7B1FA2; }}
            .btn-drop {{ background: #039BE5; border-bottom: 3px solid #0277BD; }}
            
            .controls {{ background: #f5f5f5; padding: 15px; border-radius: 10px; margin-bottom: 15px; }}
            .label {{ font-size: 11px; font-weight: bold; color: #777; letter-spacing: 1px; margin-bottom: 8px; display: block; }}
            .badge {{ padding: 5px 10px; border-radius: 12px; font-size: 12px; font-weight: bold; color: white; }}
            .badge-cpu {{ background: #78909C; }} .badge-ok {{ background: #4CAF50; }} .badge-err {{ background: #D32F2F; }}
            .footer {{ margin-top: 25px; font-size: 12px; color: #aaa; border-top: 1px solid #eee; padding-top: 15px; }}
        </style>
    </head>
    <body>
        <div class="card">
            <h1>🌱 Eco-RIC</h1>
            <div class="controls">
                <span class="label">A1 POLICY INTERFACE</span>
                <a href="/set_mode/auto" class="btn btn-a">🤖 AUTO</a>
                <a href="/set_mode/sleep" class="btn btn-s">⛔ SLEEP</a>
                <a href="/set_mode/active" class="btn btn-ac">⚡ ACTIVE</a>
            </div>
            <div class="controls" style="background: #E1F5FE;">
                <span class="label" style="color:#0277BD">DEMO TOOLS</span>
                <a href="/trigger_spike" class="btn btn-spike">🔥 SIMULATE SPIKE (99%)</a>
                <a href="/trigger_drop" class="btn btn-drop">⬇️ SIMULATE DROP (5%)</a>
            </div>
            <div class="env-box">
                <div style="text-align:left">
                    <h2 style="margin:0">{day_night_status}</h2>
                    <div style="font-size:14px; opacity:0.9">Light Level: {light_level}</div>
                </div>
                <div style="text-align:right">
                    <div>Room Temp: <b>{room_temp_str}</b></div>
                    <div>Humidity: <b>{hum_str}</b></div>
                </div>
            </div>
            <div style="display:flex; justify-content:space-around; margin: 20px 0;">
                <div>Load: <span class="big">{current_network_load}%</span></div>
                <div>AI Predict: <span class="big" style="color: purple">{int(predicted_load)}%</span></div>
            </div>
            <div class="status-box">{state_text}</div>
            <div class="footer">
                <span class="badge badge-cpu">CPU: {cpu_temp}°C</span> &nbsp; | &nbsp; {zmq_badge}
            </div>
        </div>
    </body>
    </html>
    """
    return html

if __name__ == '__main__':
    try:
        app.run(host='0.0.0.0', port=5000)
    finally:
        green_pwm.stop(); GPIO.cleanup()
